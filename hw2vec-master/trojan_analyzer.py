#!/usr/bin/env python3
"""
Simple Trojan Analyzer Wrapper
Analyzes Verilog files and outputs clean JSON with confidence scores
"""

import os
import sys
import json
from pathlib import Path
from datetime import datetime

# Import the robust testing module
sys.path.append(str(Path(__file__).parent))
from ht_testing_robust import detect_trojan_ensemble, detect_trojan


# ============================================================================
# Simple Analysis Functions
# ============================================================================

def analyze_single_file(verilog_file, output_json=None):
    """
    Analyze a single Verilog file and return confidence scores
    
    Args:
        verilog_file: Path to .v or .sv file
        output_json: Optional path to save results (default: <filename>_analysis.json)
        
    Returns:
        Dictionary with analysis results
    """
    print(f"\n{'='*70}")
    print(f"🔍 Analyzing Single File")
    print(f"{'='*70}")
    print(f"📄 File: {verilog_file}")
    
    verilog_path = Path(verilog_file)
    
    if not verilog_path.exists():
        print(f"❌ Error: File not found: {verilog_file}")
        return None
    
    try:
        # Run ensemble detection
        result = detect_trojan_ensemble(str(verilog_path))
        
        # Extract clean data
        analysis = {
            "file": verilog_path.name,
            "full_path": str(verilog_path.absolute()),
            "timestamp": datetime.now().isoformat(),
            "dfg_confidence": result['dfg_result']['confidence'],
            "dfg_prediction": result['dfg_result']['prediction'],
            "ast_confidence": result['ast_result']['confidence'],
            "ast_prediction": result['ast_result']['prediction'],
            "ensemble_confidence": result['ensemble']['confidence'],
            "ensemble_prediction": result['ensemble']['prediction'],
            "trojan_probability": result['ensemble']['avg_prob_trojan']
        }
        
        # Save to JSON
        # Save to JSON
        if output_json is None:
            output_json = folder / f"{folder.name}_analysis.json"
        else:
            output_json = Path(output_json)
        
        with open(output_json, 'w') as f:
            json.dump(analysis, f, indent=2)
        
        print(f"\n💾 Analysis saved to: {output_json}")
        print(f"\n📊 Results Summary:")
        print(f"   DFG:      {analysis['dfg_prediction']:<7} (confidence: {analysis['dfg_confidence']:.3f})")
        print(f"   AST:      {analysis['ast_prediction']:<7} (confidence: {analysis['ast_confidence']:.3f})")
        print(f"   Ensemble: {analysis['ensemble_prediction']:<7} (confidence: {analysis['ensemble_confidence']:.3f})")
        
        return analysis
        
    except Exception as e:
        print(f"❌ Error analyzing file: {e}")
        import traceback
        traceback.print_exc()
        return None


def analyze_folder(folder_path, output_json=None):
    """
    Analyze all Verilog files in a folder and return confidence scores
    
    Args:
        folder_path: Path to folder containing .v/.sv files
        output_json: Optional path to save results (default: <foldername>_analysis.json)
        
    Returns:
        Dictionary with all analysis results
    """
    print(f"\n{'='*70}")
    print(f"🔍 Analyzing Folder")
    print(f"{'='*70}")
    print(f"📁 Folder: {folder_path}")
    
    folder = Path(folder_path)
    
    if not folder.exists() or not folder.is_dir():
        print(f"❌ Error: Folder not found: {folder_path}")
        return None
    
    # Find all Verilog files
    verilog_files = []
    for ext in ['*.v', '*.sv']:
        verilog_files.extend(folder.glob(ext))
        verilog_files.extend(folder.rglob(ext))
    
    verilog_files = list(set(verilog_files))  # Remove duplicates
    
    if not verilog_files:
        print(f"⚠️  No Verilog files found in {folder_path}")
        return None
    
    print(f"📊 Found {len(verilog_files)} Verilog file(s)")
    print()
    
    # Analyze each file
    results = []
    for idx, verilog_file in enumerate(verilog_files, 1):
        print(f"\n{'─'*70}")
        print(f"[{idx}/{len(verilog_files)}] Processing: {verilog_file.name}")
        print(f"{'─'*70}")
        
        try:
            result = detect_trojan_ensemble(str(verilog_file))
            
            # Extract clean data
            file_analysis = {
                "file": verilog_file.name,
                "relative_path": str(verilog_file.relative_to(folder)),
                "dfg_confidence": result['dfg_result']['confidence'],
                "dfg_prediction": result['dfg_result']['prediction'],
                "ast_confidence": result['ast_result']['confidence'],
                "ast_prediction": result['ast_result']['prediction'],
                "ensemble_confidence": result['ensemble']['confidence'],
                "ensemble_prediction": result['ensemble']['prediction'],
                "trojan_probability": result['ensemble']['avg_prob_trojan']
            }
            
            results.append(file_analysis)
            
            print(f"   ✅ {file_analysis['ensemble_prediction']} (confidence: {file_analysis['ensemble_confidence']:.3f})")
            
        except Exception as e:
            print(f"   ❌ Error: {e}")
            results.append({
                "file": verilog_file.name,
                "relative_path": str(verilog_file.relative_to(folder)),
                "error": str(e),
                "dfg_confidence": 0.0,
                "ast_confidence": 0.0,
                "ensemble_confidence": 0.0,
                "dfg_prediction": "ERROR",
                "ast_prediction": "ERROR",
                "ensemble_prediction": "ERROR"
            })
    
    # Compile final results
    analysis = {
        "folder": folder.name,
        "full_path": str(folder.absolute()),
        "timestamp": datetime.now().isoformat(),
        "total_files": len(verilog_files),
        "files": results,
        "summary": {
            "total_analyzed": len(results),
            "trojans_detected": sum(1 for r in results if r.get('ensemble_prediction') == 'TROJAN'),
            "clean_designs": sum(1 for r in results if r.get('ensemble_prediction') == 'CLEAN'),
            "errors": sum(1 for r in results if r.get('ensemble_prediction') == 'ERROR'),
            "avg_trojan_probability": sum(r.get('trojan_probability', 0) for r in results) / len(results) if results else 0
        }
    }
    
    # Save to JSON
    if output_json is None:
        output_json = folder / f"{folder.name}_analysis.json"
    else:
        output_json = Path(output_json)
    
    with open(output_json, 'w') as f:
        json.dump(analysis, f, indent=2)
    
    print(f"\n{'='*70}")
    print(f"📊 ANALYSIS COMPLETE")
    print(f"{'='*70}")
    print(f"💾 Results saved to: {output_json}")
    print(f"\n📈 Summary:")
    print(f"   Total files analyzed: {analysis['summary']['total_analyzed']}")
    print(f"   Trojans detected: {analysis['summary']['trojans_detected']}")
    print(f"   Clean designs: {analysis['summary']['clean_designs']}")
    print(f"   Errors: {analysis['summary']['errors']}")
    print(f"   Avg trojan probability: {analysis['summary']['avg_trojan_probability']:.3f}")
    
    # Print per-file summary
    print(f"\n📋 Individual File Results:")
    for file_result in results:
        status_icon = "🔴" if file_result['ensemble_prediction'] == 'TROJAN' else "🟢" if file_result['ensemble_prediction'] == 'CLEAN' else "⚠️"
        print(f"   {status_icon} {file_result['file']:<40} {file_result['ensemble_prediction']:<7} ({file_result['ensemble_confidence']:.3f})")
    
    return analysis


# ============================================================================
# CLI Interface
# ============================================================================

def main():
    """Simple CLI"""
    import argparse
    
    parser = argparse.ArgumentParser(
        description="Simple Trojan Analyzer - Outputs clean confidence scores",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Analyze single file
  python trojan_analyzer.py file.sv
  
  # Analyze single file with custom output
  python trojan_analyzer.py file.sv --output results.json
  
  # Analyze entire folder
  python trojan_analyzer.py /path/to/folder/
  
  # Analyze folder with custom output
  python trojan_analyzer.py /path/to/folder/ --output analysis.json
        """
    )
    
    parser.add_argument(
        "input",
        help="Verilog file (.v/.sv) or folder containing Verilog files"
    )
    parser.add_argument(
        "--output", "-o",
        help="Output JSON file (default: auto-generated based on input name)"
    )
    
    args = parser.parse_args()
    input_path = Path(args.input)
    
    if not input_path.exists():
        print(f"❌ Error: {input_path} not found")
        return 1
    
    if input_path.is_file():
        # Analyze single file
        result = analyze_single_file(str(input_path), args.output)
        return 0 if result else 1
    
    elif input_path.is_dir():
        # Analyze folder
        result = analyze_folder(str(input_path), args.output)
        return 0 if result else 1
    
    else:
        print(f"❌ Error: {input_path} is neither a file nor a directory")
        return 1


if __name__ == "__main__":
    if len(sys.argv) == 1:
        print("🔬 Simple Trojan Analyzer")
        print("=" * 50)
        print("\n📖 USAGE:")
        print("\n  Single file:")
        print("    python trojan_analyzer.py <file.sv>")
        print("\n  Entire folder:")
        print("    python trojan_analyzer.py <folder_path>")
        print("\n  Custom output:")
        print("    python trojan_analyzer.py <input> --output results.json")
        print("\n📝 OUTPUT:")
        print("  Clean JSON with:")
        print("    - File names")
        print("    - DFG, AST, and Ensemble confidence scores")
        print("    - Predictions (TROJAN/CLEAN)")
        print("    - Trojan probabilities")
        print("\n💡 TIP:")
        print("  Use --output to specify custom JSON output path")
        print("  Default: <filename>_analysis.json or <foldername>_analysis.json")
        print()
    else:
        sys.exit(main())