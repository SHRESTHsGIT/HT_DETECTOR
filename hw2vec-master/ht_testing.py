#!/usr/bin/env python3
"""
Hardware Trojan Detection Testing Script
Uses pre-trained DFG and AST models to detect trojans in Verilog/SystemVerilog designs
"""

import os
import sys
import json
import shutil
import torch
from pathlib import Path
from datetime import datetime

# Add hw2vec to path
hw2vec_path = Path(__file__).parent
sys.path.append(str(hw2vec_path))

from hw2vec.hw2graph import HW2GRAPH, DataProcessor
from hw2vec.graph2vec.models import GRAPH2VEC, GRAPH_CONV, GRAPH_POOL, GRAPH_READOUT
from torch_geometric.data import DataLoader
import torch.nn as nn


# ============================================================================
# Configuration
# ============================================================================

class Config:
    """Configuration for trojan detection"""
    def __init__(self, graph_type="DFG"):
        self.device = "cpu"  # M2 Mac uses CPU
        self.dropout = 0.5
        self.graph_type = graph_type  # "DFG" or "AST"
        self.num_feature_dim = None


# ============================================================================
# Model Loading
# ============================================================================

def load_pretrained_model(model_type="DFG"):
    """
    Load pre-trained trojan detection model
    
    Args:
        model_type: "DFG" or "AST"
        
    Returns:
        Loaded GRAPH2VEC model
    """
    print(f"📥 Loading {model_type} pre-trained model...")
    
    # Model paths
    if model_type == "DFG":
        cfg_path = hw2vec_path / "trained_models" / "pretrained_DFG_TJ_RTL" / "model.cfg"
        pth_path = hw2vec_path / "trained_models" / "pretrained_DFG_TJ_RTL" / "model.pth"
    else:  # AST
        cfg_path = hw2vec_path / "trained_models" / "pretrained_AST_TJ_RTL" / "model.cfg"
        pth_path = hw2vec_path / "trained_models" / "pretrained_AST_TJ_RTL" / "model.pth"
    
    # Create config
    cfg = Config(graph_type=model_type)
    
    # Initialize model
    model = GRAPH2VEC(cfg)
    
    # Load model configuration
    with open(cfg_path) as f:
        model_config = json.load(f)
    
    # Build architecture
    convs = []
    for setting in model_config['convs']:
        graph_conv_type, in_channels, out_channels = setting
        convs.append(GRAPH_CONV(graph_conv_type, int(in_channels), int(out_channels)))
    model.set_graph_conv(convs)
    
    pool_type, pool_in_channels, pool_ratio = model_config['pool']
    model.set_graph_pool(GRAPH_POOL(pool_type, pool_in_channels, pool_ratio))
    
    model.set_graph_readout(GRAPH_READOUT(model_config['readout']))
    
    fc_in, fc_out = model_config['fc']
    model.set_output_layer(nn.Linear(fc_in, fc_out))
    
    # Load weights with CPU mapping
    model.load_state_dict(torch.load(pth_path, map_location='cpu'))
    model.to(cfg.device)
    model.eval()
    
    print(f"   ✅ {model_type} model loaded successfully")
    return model, cfg


# ============================================================================
# Graph Generation
# ============================================================================

def verilog_to_graph(verilog_file, graph_type="DFG"):
    """
    Convert Verilog/SystemVerilog file to graph
    
    Args:
        verilog_file: Path to .v or .sv file
        graph_type: "DFG" or "AST"
        
    Returns:
        Processed graph data
    """
    print(f"🔄 Converting {Path(verilog_file).name} to {graph_type} graph...")
    
    # Create temporary directory structure
    temp_dir = Path("/tmp/ht_test") / f"test_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    design_dir = temp_dir / "design"
    design_dir.mkdir(parents=True, exist_ok=True)
    
    # Copy file to temp directory
    temp_file = design_dir / Path(verilog_file).name
    shutil.copy(verilog_file, temp_file)
    
    # Create config
    cfg = Config(graph_type=graph_type)
    cfg.raw_dataset_path = temp_dir
    
    # Generate graph
    hw2graph = HW2GRAPH(cfg)
    hw_graph = hw2graph.code2graph(design_dir, profile=False)
    
    # Process graph
    data_proc = DataProcessor(cfg)
    data_proc.process(hw_graph)
    graphs = data_proc.get_graphs()
    
    # Cleanup temp directory
    shutil.rmtree(temp_dir)
    
    print(f"   ✅ Graph generated ({len(hw_graph.nodes)} nodes, {len(hw_graph.edges)} edges)")
    return graphs, cfg


# ============================================================================
# Trojan Detection
# ============================================================================

def detect_trojan(verilog_file, model_type="DFG", model=None, cfg=None):
    """
    Detect hardware trojan in a Verilog design
    
    Args:
        verilog_file: Path to .v or .sv file
        model_type: "DFG" or "AST"
        model: Pre-loaded model (optional, will load if None)
        cfg: Model config (optional)
        
    Returns:
        Detection result dictionary
    """
    # Load model if not provided
    if model is None:
        model, cfg = load_pretrained_model(model_type)
    
    # Convert to graph
    graphs, graph_cfg = verilog_to_graph(verilog_file, model_type)
    
    # Run inference
    print(f"🧪 Running {model_type} detection...")
    loader = DataLoader(graphs, batch_size=1)
    data = next(iter(loader)).to(cfg.device)
    
    with torch.no_grad():
        graph_embed, _ = model.embed_graph(data.x, data.edge_index, data.batch)
        output = model.mlp(graph_embed)
        probabilities = torch.softmax(output, dim=1)
        prediction = output.max(1)[1].item()
    
    result = {
        "file": str(verilog_file),
        "model": model_type,
        "prediction": "TROJAN" if prediction == 1 else "CLEAN",
        "confidence": probabilities[0][prediction].item(),
        "prob_clean": probabilities[0][0].item(),
        "prob_trojan": probabilities[0][1].item(),
        "timestamp": datetime.now().isoformat()
    }
    
    print(f"   🎯 Result: {result['prediction']} (confidence: {result['confidence']:.3f})")
    return result


def detect_trojan_ensemble(verilog_file):
    """
    Detect trojan using both DFG and AST models (ensemble)
    
    Args:
        verilog_file: Path to .v or .sv file
        
    Returns:
        Combined result dictionary
    """
    print(f"\n{'='*70}")
    print(f"🔬 HARDWARE TROJAN DETECTION - ENSEMBLE MODE")
    print(f"{'='*70}")
    print(f"📄 File: {verilog_file}")
    print()
    
    # Load both models
    dfg_model, dfg_cfg = load_pretrained_model("DFG")
    ast_model, ast_cfg = load_pretrained_model("AST")
    
    # Test with DFG
    print()
    dfg_result = detect_trojan(verilog_file, "DFG", dfg_model, dfg_cfg)
    
    # Test with AST
    print()
    ast_result = detect_trojan(verilog_file, "AST", ast_model, ast_cfg)
    
    # Ensemble decision
    avg_prob_trojan = (dfg_result['prob_trojan'] + ast_result['prob_trojan']) / 2
    avg_prob_clean = (dfg_result['prob_clean'] + ast_result['prob_clean']) / 2
    
    # Vote-based: if either detects trojan with >0.6 confidence
    if dfg_result['prob_trojan'] > 0.6 or ast_result['prob_trojan'] > 0.6:
        ensemble_pred = "TROJAN"
        ensemble_conf = max(dfg_result['prob_trojan'], ast_result['prob_trojan'])
    else:
        ensemble_pred = "CLEAN"
        ensemble_conf = max(dfg_result['prob_clean'], ast_result['prob_clean'])
    
    result = {
        "file": str(verilog_file),
        "dfg_result": dfg_result,
        "ast_result": ast_result,
        "ensemble": {
            "prediction": ensemble_pred,
            "confidence": ensemble_conf,
            "avg_prob_trojan": avg_prob_trojan,
            "avg_prob_clean": avg_prob_clean
        },
        "timestamp": datetime.now().isoformat()
    }
    
    print()
    print(f"{'='*70}")
    print(f"📊 FINAL RESULTS:")
    print(f"{'='*70}")
    print(f"   DFG:      {dfg_result['prediction']:<7} (confidence: {dfg_result['confidence']:.3f})")
    print(f"   AST:      {ast_result['prediction']:<7} (confidence: {ast_result['confidence']:.3f})")
    print(f"   Ensemble: {ensemble_pred:<7} (confidence: {ensemble_conf:.3f})")
    print(f"{'='*70}")
    
    return result


# ============================================================================
# Batch Testing
# ============================================================================

def test_directory(directory, output_file="detection_results.json", model_type="ensemble"):
    """
    Test all Verilog files in a directory
    
    Args:
        directory: Path to directory containing .v or .sv files
        output_file: Where to save results
        model_type: "DFG", "AST", or "ensemble"
        
    Returns:
        List of results
    """
    print(f"\n{'='*70}")
    print(f"🔬 BATCH HARDWARE TROJAN DETECTION")
    print(f"{'='*70}")
    print(f"📁 Directory: {directory}")
    print(f"🎯 Model: {model_type}")
    print()
    
    # Find all Verilog files
    verilog_files = []
    for ext in ['*.v', '*.sv']:
        verilog_files.extend(Path(directory).glob(ext))
        verilog_files.extend(Path(directory).rglob(ext))
    
    verilog_files = list(set(verilog_files))  # Remove duplicates
    
    print(f"📊 Found {len(verilog_files)} Verilog files")
    print()
    
    # Test each file
    results = []
    for idx, verilog_file in enumerate(verilog_files, 1):
        print(f"\n[{idx}/{len(verilog_files)}] Testing: {verilog_file.name}")
        print("-" * 70)
        
        try:
            if model_type == "ensemble":
                result = detect_trojan_ensemble(str(verilog_file))
            else:
                result = detect_trojan(str(verilog_file), model_type)
            
            results.append(result)
        except Exception as e:
            print(f"   ❌ Error: {e}")
            results.append({
                "file": str(verilog_file),
                "error": str(e),
                "timestamp": datetime.now().isoformat()
            })
    
    # Save results
    output_path = Path(output_file)
    with open(output_path, 'w') as f:
        json.dump({
            "metadata": {
                "directory": str(directory),
                "total_files": len(verilog_files),
                "model_type": model_type,
                "timestamp": datetime.now().isoformat()
            },
            "results": results
        }, f, indent=2)
    
    print(f"\n{'='*70}")
    print(f"💾 Results saved to: {output_path}")
    print(f"{'='*70}")
    
    # Print summary
    if model_type == "ensemble":
        trojans_detected = sum(1 for r in results if r.get('ensemble', {}).get('prediction') == "TROJAN")
    else:
        trojans_detected = sum(1 for r in results if r.get('prediction') == "TROJAN")
    
    print(f"\n📊 SUMMARY:")
    print(f"   Total files tested: {len(results)}")
    print(f"   Trojans detected: {trojans_detected}")
    print(f"   Clean designs: {len(results) - trojans_detected}")
    
    return results


# ============================================================================
# Main CLI Interface
# ============================================================================

def main():
    """Main command-line interface"""
    import argparse
    
    parser = argparse.ArgumentParser(
        description="Hardware Trojan Detection using GNN-based models"
    )
    parser.add_argument(
        "input",
        help="Verilog file (.v/.sv) or directory to test"
    )
    parser.add_argument(
        "--model",
        choices=["DFG", "AST", "ensemble"],
        default="ensemble",
        help="Model type to use (default: ensemble)"
    )
    parser.add_argument(
        "--output",
        default="detection_results.json",
        help="Output file for results (default: detection_results.json)"
    )
    
    args = parser.parse_args()
    
    input_path = Path(args.input)
    
    if input_path.is_file():
        # Test single file
        if args.model == "ensemble":
            result = detect_trojan_ensemble(str(input_path))
        else:
            result = detect_trojan(str(input_path), args.model)
        
        # Save result
        with open(args.output, 'w') as f:
            json.dump(result, f, indent=2)
        
        print(f"\n💾 Result saved to: {args.output}")
    
    elif input_path.is_dir():
        # Test directory
        test_directory(str(input_path), args.output, args.model)
    
    else:
        print(f"❌ Error: {input_path} not found")
        return 1
    
    return 0


if __name__ == "__main__":
    # Example usage if run directly
    import sys
    
    if len(sys.argv) == 1:
        print("🔬 Hardware Trojan Detection Tool")
        print("=" * 50)
        print("\n📖 USAGE:")
        print("\n1. Test single file:")
        print("   python ht_testing.py design.sv")
        print("\n2. Test single file with specific model:")
        print("   python ht_testing.py design.sv --model DFG")
        print("\n3. Test all files in directory:")
        print("   python ht_testing.py /path/to/designs/")
        print("\n4. Test directory with custom output:")
        print("   python ht_testing.py /path/to/designs/ --output my_results.json")
        print("\n📝 EXAMPLES:")
        print("\n   # Test your original design")
        print("   python ht_testing.py RISCV_ORIGINAL.sv")
        print("\n   # Test all trojan variants")
        print("   python ht_testing.py trojan_output/complete_integrated_files/")
        print("\n   # Use ensemble (both DFG and AST)")
        print("   python ht_testing.py design.sv --model ensemble")
        print()
    else:
        sys.exit(main())