#!/usr/bin/env python3
"""
Train Hardware Trojan Detection Model on TJ-RTL-toy Dataset
SAVES TRAINED MODELS FOR FUTURE DETECTION
"""

import os
import sys
import torch
import torch.nn as nn
import yaml
from pathlib import Path

# Add hw2vec to path
hw2vec_path = Path(__file__).parent
sys.path.append(str(hw2vec_path))

from hw2vec.config import Config
from hw2vec.hw2graph import HW2GRAPH, DataProcessor
from hw2vec.graph2vec.models import GRAPH2VEC, GRAPH_CONV, GRAPH_POOL, GRAPH_READOUT
from hw2vec.graph2vec.trainers import GraphTrainer
from torch_geometric.data import DataLoader


def create_config_yaml(output_path, epochs=200, hidden=200, batch_size=4):
    """Create YAML config file for hw2vec"""
    config = {
        'learning_rate': 0.001,
        'seed': 42,
        'epochs': epochs,
        'hidden': hidden,
        'dropout': 0.5,
        'batch_size': batch_size,
        'num_layer': 2,
        'test_step': 10,
        'pooling_type': 'sagpool',
        'readout_type': 'max',
        'ratio': 0.8,
        'poolratio': 0.8,
        'embed_dim': 2
    }
    
    with open(output_path, 'w') as f:
        yaml.dump(config, f)
    
    return output_path


def train_trojan_detector(
    dataset_path="/Users/shresthshankhdhar/Documents/RESEARCH/HT_DES/hw2vec-master/assets/TJ-RTL-toy",
    graph_type="DFG",
    output_pkl="tj_rtl_graphs.pkl",
    output_model_dir="trained_trojan_model",
    epochs=200,
    hidden=200,
    batch_size=4,
    device="cpu"
):
    """
    Train hardware trojan detection model on TJ-RTL-toy dataset
    """
    
    print(f"\n{'='*70}")
    print(f"🚀 TRAINING HARDWARE TROJAN DETECTOR")
    print(f"{'='*70}")
    print(f"📊 Dataset: {dataset_path}")
    print(f"🔧 Graph Type: {graph_type}")
    print(f"💾 Model Output: {output_model_dir}")
    print(f"{'='*70}\n")
    
    # Create YAML config file
    output_dir = Path(output_model_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    yaml_path = output_dir / "training_config.yaml"
    create_config_yaml(yaml_path, epochs, hidden, batch_size)
    print(f"✅ Created config: {yaml_path}")
    
    # Create config with correct arguments
    args = [
        '--yaml_path', str(yaml_path),
        '--raw_dataset_path', dataset_path,
        '--data_pkl_path', output_pkl,
        '--graph_type', graph_type,
        '--device', device
    ]
    
    cfg = Config(args)
    
    # ========================================================================
    # STEP 1: Prepare Graph Data
    # ========================================================================
    
    data_pkl_path = Path(output_pkl)
    
    if not data_pkl_path.exists():
        print("\n📊 STEP 1: Converting hardware designs to graphs...")
        print(f"   Graph type: {graph_type}")
        
        nx_graphs = []
        hw2graph = HW2GRAPH(cfg)
        
        for hw_project_path in hw2graph.find_hw_project_folders():
            print(f"   Processing: {hw_project_path.name}")
            hw_graph = hw2graph.code2graph(hw_project_path)
            nx_graphs.append(hw_graph)
        
        print(f"   ✅ Converted {len(nx_graphs)} designs to graphs")
        
        # Process graphs
        data_proc = DataProcessor(cfg)
        for hw_graph in nx_graphs:
            data_proc.process(hw_graph)
        
        # Cache to disk
        data_proc.cache_graph_data(data_pkl_path)
        print(f"   ✅ Cached graphs to: {output_pkl}")
        
    else:
        print("\n📦 STEP 1: Reading cached graph data...")
        data_proc = DataProcessor(cfg)
        data_proc.read_graph_data_from_cache(data_pkl_path)
        print(f"   ✅ Loaded from cache: {output_pkl}")
    
    # ========================================================================
    # STEP 2: Prepare Dataset
    # ========================================================================
    
    print("\n📋 STEP 2: Preparing dataset...")
    
    TROJAN = 1
    NON_TROJAN = 0
    
    all_graphs = data_proc.get_graphs()
    
    # Label graphs
    for data in all_graphs:
        if "TjFree" == data.hw_type:
            data.label = NON_TROJAN
        else:
            data.label = TROJAN
    
    # Split into train/test
    train_graphs, test_graphs = data_proc.split_dataset(
        ratio=cfg.ratio, 
        seed=cfg.seed, 
        dataset=all_graphs
    )
    
    # Count labels
    train_clean = sum(1 for g in train_graphs if g.label == NON_TROJAN)
    train_trojan = len(train_graphs) - train_clean
    test_clean = sum(1 for g in test_graphs if g.label == NON_TROJAN)
    test_trojan = len(test_graphs) - test_clean
    
    print(f"   Total graphs: {len(all_graphs)}")
    print(f"   Training: {len(train_graphs)} ({train_clean} clean, {train_trojan} trojan)")
    print(f"   Testing: {len(test_graphs)} ({test_clean} clean, {test_trojan} trojan)")
    print(f"   Node feature dim: {data_proc.num_node_labels}")
    
    # Create data loaders
    train_loader = DataLoader(train_graphs, shuffle=True, batch_size=cfg.batch_size)
    valid_loader = DataLoader(test_graphs, shuffle=True, batch_size=1)
    
    # ========================================================================
    # STEP 3: Build Model
    # ========================================================================
    
    print("\n🏗️  STEP 3: Building GNN model...")
    
    model = GRAPH2VEC(cfg)
    
    # Build architecture
    convs = [
        GRAPH_CONV("gcn", data_proc.num_node_labels, cfg.hidden),
        GRAPH_CONV("gcn", cfg.hidden, cfg.hidden)
    ]
    model.set_graph_conv(convs)
    
    pool = GRAPH_POOL("sagpool", cfg.hidden, cfg.poolratio)
    model.set_graph_pool(pool)
    
    readout = GRAPH_READOUT("max")
    model.set_graph_readout(readout)
    
    output_layer = nn.Linear(cfg.hidden, cfg.embed_dim)
    model.set_output_layer(output_layer)
    
    model.to(cfg.device)
    
    print(f"   ✅ Model architecture:")
    print(f"      Input features: {data_proc.num_node_labels}")
    print(f"      Hidden dim: {cfg.hidden}")
    print(f"      Output classes: {cfg.embed_dim}")
    print(f"      Device: {cfg.device}")
    
    # ========================================================================
    # STEP 4: Train Model
    # ========================================================================
    
    print(f"\n🎯 STEP 4: Training model...")
    print(f"   Epochs: {cfg.epochs}")
    print(f"   Batch size: {cfg.batch_size}")
    print()
    
    # Get class weights
    class_weights = data_proc.get_class_weights(train_graphs)
    
    # Build trainer
    trainer = GraphTrainer(cfg, class_weights=class_weights)
    trainer.build(model)
    
    # Train
    trainer.train(train_loader, valid_loader)
    
    # ========================================================================
    # STEP 5: Evaluate
    # ========================================================================
    
    print(f"\n📊 STEP 5: Final evaluation...")
    trainer.evaluate(cfg.epochs, train_loader, valid_loader)
    
    # ========================================================================
    # STEP 6: Save Model
    # ========================================================================
    
    print(f"\n💾 STEP 6: Saving trained model...")
    
    model_path = output_dir / "model.pth"
    config_path = output_dir / "model.cfg"
    
    torch.save(model.state_dict(), model_path)
    
    # Save config
    import json
    model_config = {
        'graph_type': graph_type,
        'num_features': data_proc.num_node_labels,
        'hidden_dim': cfg.hidden,
        'embed_dim': cfg.embed_dim,
        'convs': [
            ["gcn", data_proc.num_node_labels, cfg.hidden],
            ["gcn", cfg.hidden, cfg.hidden]
        ],
        'pool': ["sagpool", cfg.hidden, cfg.poolratio],
        'readout': "max",
        'fc': [cfg.hidden, cfg.embed_dim]
    }
    
    with open(config_path, 'w') as f:
        json.dump(model_config, f, indent=2)
    
    print(f"   ✅ Model weights: {model_path.absolute()}")
    print(f"   ✅ Model config: {config_path.absolute()}")
    
    # ========================================================================
    # STEP 7: Visualize
    # ========================================================================
    
    print(f"\n🎨 STEP 7: Visualizing embeddings...")
    vis_loader = DataLoader(all_graphs, shuffle=False, batch_size=1)
    trainer.visualize_embeddings(vis_loader, str(output_dir))
    
    print(f"\n{'='*70}")
    print(f"✅ TRAINING COMPLETE!")
    print(f"📁 Model: {output_dir.absolute()}")
    print(f"{'='*70}\n")
    
    return str(model_path.absolute()), str(config_path.absolute())


# ============================================================================
# Main
# ============================================================================

if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", default="/Users/shresthshankhdhar/Documents/RESEARCH/HT_DES/hw2vec-master/assets/TJ-RTL-toy")
    parser.add_argument("--graph-type", choices=['DFG', 'AST', 'BOTH'], default='BOTH')
    parser.add_argument("--epochs", type=int, default=200)
    parser.add_argument("--device", default='cpu')
    parser.add_argument("--output-dir", default="/Users/shresthshankhdhar/Documents/RESEARCH/HT_DES/hw2vec-master/trained_models")
    
    args = parser.parse_args()
    
    output_base = Path(args.output_dir)
    output_base.mkdir(parents=True, exist_ok=True)
    
    print(f"\n{'='*70}")
    print(f"🎯 TRAINING HARDWARE TROJAN DETECTION MODELS")
    print(f"{'='*70}")
    print(f"📊 Dataset: {args.dataset}")
    print(f"🔧 Type: {args.graph_type}")
    print(f"💾 Output: {output_base.absolute()}")
    print(f"{'='*70}")
    
    if args.graph_type in ['DFG', 'BOTH']:
        print("\n" + "="*70)
        print("🔷 TRAINING DFG MODEL")
        print("="*70)
        
        train_trojan_detector(
            dataset_path=args.dataset,
            graph_type='DFG',
            output_pkl=str(output_base / "tj_rtl_dfg_graphs.pkl"),
            output_model_dir=str(output_base / "pretrained_DFG_TJ_RTL"),
            epochs=args.epochs,
            device=args.device
        )
    
    if args.graph_type in ['AST', 'BOTH']:
        print("\n" + "="*70)
        print("🔶 TRAINING AST MODEL")
        print("="*70)
        
        train_trojan_detector(
            dataset_path=args.dataset,
            graph_type='AST',
            output_pkl=str(output_base / "tj_rtl_ast_graphs.pkl"),
            output_model_dir=str(output_base / "pretrained_AST_TJ_RTL"),
            epochs=args.epochs,
            device=args.device
        )
    
    print("\n" + "="*70)
    print("🎉 ALL MODELS TRAINED!")
    print(f"📁 Location: {output_base.absolute()}")
    print("="*70 + "\n")