#!/usr/bin/env python3
"""
Robust Hardware Trojan Detection Script
Handles real-world Verilog files without preprocessing bugs
"""
import pygraphviz as pgv
from pygraphviz import AGraph
import os
import sys
import json
import shutil
import torch
import re
from pathlib import Path
from datetime import datetime


# Add hw2vec to path
hw2vec_path = Path(__file__).parent
sys.path.append(str(hw2vec_path))

from hw2vec.hw2graph import DataProcessor
from hw2vec.graph2vec.models import GRAPH2VEC, GRAPH_CONV, GRAPH_POOL, GRAPH_READOUT
from torch_geometric.data import DataLoader
import torch.nn as nn

# Import only the parts of hw2vec we need
from pyverilog.vparser.parser import parse
from pyverilog.dataflow.optimizer import VerilogDataflowOptimizer
from pyverilog.dataflow.graphgen import VerilogGraphGenerator
from pyverilog.controlflow.controlflow_analyzer import VerilogControlflowAnalyzer
import networkx as nx

# ============================================================================
# MONKEY PATCH: Fix pyverilog's missing pygraphviz import
# ============================================================================
import sys
import pygraphviz as pgv
from pygraphviz import AGraph

# Inject pygraphviz into pyverilog's graphgen module namespace
try:
    from pyverilog.dataflow import graphgen
    if not hasattr(graphgen, 'pgv'):
        graphgen.pgv = pgv
        graphgen.AGraph = AGraph
        print("✅ Monkey patched pyverilog.dataflow.graphgen with pygraphviz")
except ImportError:
    print("⚠️  Could not import pyverilog.dataflow.graphgen for monkey patching")
except Exception as e:
    print(f"⚠️  Monkey patch failed: {e}")

# ============================================================================
# Configuration
# ============================================================================

class Config:
    """Configuration for trojan detection"""
    def __init__(self, graph_type="DFG"):
        self.device = "cpu"
        self.dropout = 0.5
        self.graph_type = graph_type
        self.num_feature_dim = None


# ============================================================================
# Verilog File Preprocessing (Robust Version)
# ============================================================================

def extract_main_module(verilog_file):
    """
    Extract the main module from a Verilog file
    Skips testbenches and helper modules
    
    Returns: (module_name, module_code)
    """
    with open(verilog_file, 'r') as f:
        content = f.read()
    
    # Find all modules
    module_pattern = r'module\s+(\w+)'
    modules = re.findall(module_pattern, content)
    
    if not modules:
        raise ValueError(f"No modules found in {verilog_file}")
    
    # Filter out testbenches
    main_modules = [m for m in modules if not m.endswith('_tb') and 'tb' not in m.lower() and 'test' not in m.lower()]
    
    if not main_modules:
        main_module = modules[0]  # Fallback to first module
    else:
        main_module = main_modules[0]  # Use first non-testbench module
    
    print(f"   📌 Detected main module: {main_module}")
    
    # Extract that module's code
    module_start = content.find(f"module {main_module}")
    if module_start == -1:
        return main_module, content  # Return full file if extraction fails
    
    # Find corresponding endmodule
    depth = 0
    module_end = module_start
    i = module_start
    while i < len(content):
        if content[i:i+6] == 'module':
            depth += 1
        elif content[i:i+9] == 'endmodule':
            depth -= 1
            if depth == 0:
                module_end = i + 9
                break
        i += 1
    
    module_code = content[module_start:module_end]
    
    # Rename to 'top' for hw2vec compatibility
    module_code = module_code.replace(f"module {main_module}", "module top", 1)
    
    return main_module, module_code


def prepare_verilog_file(verilog_file, output_dir):
    """
    Prepare Verilog file for hw2vec processing
    
    Args:
        verilog_file: Input .v or .sv file
        output_dir: Where to save prepared file
        
    Returns:
        Path to prepared file
    """
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # Extract main module
    original_name, module_code = extract_main_module(verilog_file)
    
    # Convert SystemVerilog to Verilog
    # Remove 'int' type from localparams
    module_code = re.sub(r'localparam\s+int\s+', 'localparam ', module_code)
    # Remove 'logic' and replace with 'reg' or 'wire'
    module_code = re.sub(r'\binput\s+logic\b', 'input wire', module_code)
    module_code = re.sub(r'\boutput\s+logic\b', 'output reg', module_code)
    module_code = re.sub(r'\blogic\b', 'reg', module_code)
    # Remove typedef enum (convert to simple parameters)
    module_code = re.sub(r'typedef\s+enum.*?\}\s*\w+;', '// enum removed', module_code, flags=re.DOTALL)
    
    # Save as topModule.v
    output_file = output_dir / "topModule.v"
    with open(output_file, 'w') as f:
        f.write(module_code)
    
    print(f"   ✅ Prepared: {original_name} → top")
    return output_file


# ============================================================================
# Direct Graph Generation (Bypasses hw2vec preprocessing)
# ============================================================================

class RobustDFGGenerator:
    """Generate DFG graphs directly without hw2vec's buggy preprocessing"""
    
    def process(self, verilog_file):
        """
        Generate DFG from Verilog file
        
        Args:
            verilog_file: Path to prepared Verilog file
            
        Returns:
            NetworkX graph
        """
        try:
            # Import VerilogDataflowAnalyzer directly from utilities (it's already defined there)
            from hw2vec.utilities import VerilogDataflowAnalyzer
            
            # Import the other components directly from pyverilog
            from pyverilog.dataflow.optimizer import VerilogDataflowOptimizer
            from pyverilog.dataflow.graphgen import VerilogGraphGenerator
            
            # Analyze dataflow
            dataflow_analyzer = VerilogDataflowAnalyzer([str(verilog_file)], "top")
            dataflow_analyzer.generate()
            binddict = dataflow_analyzer.getBinddict()
            terms = dataflow_analyzer.getTerms()
            
            # Optimize
            dataflow_optimizer = VerilogDataflowOptimizer(terms, binddict)
            dataflow_optimizer.resolveConstant()
            resolved_terms = dataflow_optimizer.getResolvedTerms()
            resolved_binddict = dataflow_optimizer.getResolvedBinddict()
            constlist = dataflow_optimizer.getConstlist()
            
            # Generate DFG
            dfg_graph_generator = VerilogGraphGenerator("top", terms, binddict, 
                                                       resolved_terms, resolved_binddict, 
                                                       constlist, None)
            
            # Generate graph for all signals
            signals = [str(bind) for bind in dfg_graph_generator.binddict]
            for signal in sorted(signals, key=str.casefold):
                dfg_graph_generator.generate(signal, walk=False)
            
            # Convert pygraphviz AGraph to NetworkX
            nx_graph = nx.DiGraph()
            
            # The graph is a pygraphviz AGraph object
            # Access it directly from the generator
            pgv_graph = dfg_graph_generator.graph
            
            for node in pgv_graph.nodes():
                node_name = str(node)
                display_name = node_name
                
                if '_graphrename' in node_name:
                    display_name = node_name[:node_name.index('_graphrename')]
                
                # Determine node type from name
                if '.' in display_name:
                    type_of_node = display_name.split('.')[-1]
                elif '_' in display_name:
                    type_of_node = display_name.split('_')[-1]
                else:
                    type_of_node = display_name.lower()
                
                nx_graph.add_node(node_name, label=type_of_node)
            
            # Add all edges
            for edge in pgv_graph.edges():
                src, dst = edge
                nx_graph.add_edge(str(src), str(dst))
            
            print(f"   ✅ DFG graph generated ({len(nx_graph.nodes())} nodes, {len(nx_graph.edges())} edges)")
            print("\n🔍 DEBUG: Node label distribution")
            from collections import Counter
            labels = [data['label'] for _, data in nx_graph.nodes(data=True)]
            label_counts = Counter(labels)
            print(f"   Total unique labels: {len(label_counts)}")
            print(f"   Top 10 labels: {label_counts.most_common(10)}")

            # Also check what the DataProcessor expects
            print("\n🔍 DEBUG: Checking DataProcessor vocabulary")

            return nx_graph
            
        except Exception as e:
            print(f"   ⚠️  DFG generation failed: {e}")
            import traceback
            traceback.print_exc()
            raise


class RobustASTGenerator:
    """Generate AST graphs directly"""
    
    def process(self, verilog_file):
        """Generate AST from Verilog file"""
        try:
            ast, _ = parse([str(verilog_file)], debug=False)
            
            nx_graph = nx.DiGraph()
            counter = [0]  # Use list for mutable counter
            
            def add_node_recursive(graph, parent, child, cur_dict):
                index = counter[0]
                counter[0] += 1
                
                graph.add_nodes_from([(index, {"label": str(child)})])
                if parent != 'None':
                    graph.add_edge(parent, index)
                
                if type(cur_dict) == dict:
                    for key in cur_dict.keys():
                        add_node_recursive(graph, index, key, cur_dict[key])
                elif type(cur_dict) == list:
                    for ele in cur_dict:
                        if type(ele) == dict:
                            add_node_recursive(graph, index, 'None', ele)
                        elif ele is not None:
                            node_idx = counter[0]
                            counter[0] += 1
                            graph.add_nodes_from([(node_idx, {"label": str(ele)})])
                            graph.add_edge(index, node_idx)
                else:
                    node_idx = counter[0]
                    counter[0] += 1
                    graph.add_nodes_from([(node_idx, {"label": str(cur_dict)})])
                    graph.add_edge(index, node_idx)
            
            # Generate AST dict
            ast_dict = self._generate_ast_dict(ast)
            for key in ast_dict.keys():
                add_node_recursive(nx_graph, 'None', key, ast_dict[key])
            
            return nx_graph
            
        except Exception as e:
            print(f"   ⚠️  AST generation failed: {e}")
            raise
    
    def _generate_ast_dict(self, ast_node):
        """Generate nested dictionary for AST"""
        DICTIONARY_GEN = ["Source", "Description", "Ioport", "Decl", "Lvalue"]
        ARRAY_GEN = ["ModuleDef", "Paramlist", "Portlist", "Input", "Width", "Reg", 
                     "Wire", "Rvalue", "ParseSelect", "Always", "Block", "Assign", 
                     "IfStatement", "Output", "Port", "Identifier", "IntConst"]
        CONST_DICTIONARY_GEN = ["IntConst", "FloatConst", "StringConst", "Identifier"]
        
        class_name = ast_node.__class__.__name__
        structure = {}
        
        if class_name in ARRAY_GEN:
            structure[class_name] = [getattr(ast_node, n) for n in ast_node.attr_names] if ast_node.attr_names else []
            for c in ast_node.children():
                structure[class_name].append(self._generate_ast_dict(c))
        elif class_name in DICTIONARY_GEN:
            structure[class_name] = self._generate_ast_dict(ast_node.children()[0])
        elif class_name in CONST_DICTIONARY_GEN:
            structure[class_name] = getattr(ast_node, ast_node.attr_names[0])
        else:
            # Handle unknown types gracefully
            structure[class_name] = str(ast_node)
        
        return structure

# ============================================================================
# Fixed Vocabulary Data Processor
# ============================================================================

class FixedVocabDataProcessor:
    """
    DataProcessor that uses the exact vocabulary from training
    This ensures 100% compatibility with pre-trained models
    """
    def __init__(self, cfg, vocab_size=37):
        self.cfg = cfg
        self.vocab_size = vocab_size
        self.graphs = []
        
        # EXACT vocabulary from training (extracted from TJ-RTL-toy dataset)
        self.fixed_vocab = [
            'branch', 'eq', 'partselect', "'d0", 'lor', 'unot', "'d1", 'concat',
            "'d7", 'land', "'d4", "'d2", "'d31", "'d3", "1'd0", 'state', 'dout',
            'reg', "3'd0", "3'd3", "1'd1", "3'd2", "3'd5", "'d6", "'d13", "3'd4",
            "'d8", 'plus', 'D', "3'd1", "'d5", 'bitCountH', 'SWAP', 'and', "'d10",
            'i', "2'd1"
        ]
        
        # Verify vocabulary size
        assert len(self.fixed_vocab) == vocab_size, f"Vocabulary size mismatch: {len(self.fixed_vocab)} != {vocab_size}"
        
        self.label_to_idx = {label: idx for idx, label in enumerate(self.fixed_vocab)}
        # CRITICAL: Set this on the config object so the model can use it
        self.cfg.num_feature_dim = vocab_size
        
        print(f"   📚 Using exact training vocabulary ({vocab_size} node types)")
        print(f"   📌 Set cfg.num_feature_dim = {vocab_size}")
    
    def process(self, hw_graph):
        """Process graph with fixed vocabulary"""
        import torch
        from torch_geometric.data import Data
        
        # Map nodes to indices
        node_to_idx = {node: idx for idx, node in enumerate(hw_graph.nodes())}
        
        # Create node features as LABEL INDICES (not one-hot)
        # The model will handle one-hot encoding internally
        node_features = []
        unmapped_labels = set()
        mapped_count = 0
        
        for node, data in hw_graph.nodes(data=True):
            label = data.get('label', 'unknown')
            
            # Try exact match first
            if label in self.label_to_idx:
                label_idx = self.label_to_idx[label]
                mapped_count += 1
            else:
                # Try to map to similar label
                label_idx = self._map_label(label)
                if label_idx is not None:
                    mapped_count += 1
                else:
                    unmapped_labels.add(label)
                    # Map to most common type: 'branch'
                    label_idx = 0
            
            # Store the INDEX, not one-hot vector
            node_features.append(label_idx)
        
        if unmapped_labels:
            print(f"   ⚠️  {len(unmapped_labels)} unknown labels mapped to 'branch': {list(unmapped_labels)[:3]}...")
        print(f"   ✓ Mapped {mapped_count}/{len(hw_graph.nodes())} nodes to vocabulary")
        
        # Create edge indices
        edge_index = []
        for src, dst in hw_graph.edges():
            edge_index.append([node_to_idx[src], node_to_idx[dst]])
        
        if not edge_index:
            edge_index = [[0, 0]]  # Self-loop if no edges
        
        # Convert to PyTorch tensors
        # CRITICAL: Store as LONG tensor (indices), not float!
        x = torch.tensor(node_features, dtype=torch.long)
        edge_index = torch.tensor(edge_index, dtype=torch.long).t().contiguous()
        
        # Create PyG Data object
        data = Data(x=x, edge_index=edge_index)
        data.name = hw_graph.name
        data.type = getattr(hw_graph, 'type', 'Unknown')
        
        self.graphs.append(data)
    
    def _map_label(self, label):
        """Try to map unknown label to known vocabulary"""
        label_lower = label.lower().strip()
        
        # Handle various constant formats
        # 'd0, 'd1, etc. -> map to closest match
        if label.startswith("'d"):
            num = label[2:]
            for vocab_label in self.fixed_vocab:
                if vocab_label.startswith("'d") and vocab_label[2:] == num:
                    return self.label_to_idx[vocab_label]
            # Default to 'd0
            return self.label_to_idx.get("'d0")
        
        # Handle bit-width constants: 1'd0, 2'd1, 3'd0, etc.
        if "'" in label and 'd' in label:
            # Try exact match first
            if label in self.label_to_idx:
                return self.label_to_idx[label]
            # Try to find similar width
            parts = label.split("'d")
            if len(parts) == 2:
                value = parts[1]
                # Look for any match with same value
                for vocab_label in self.fixed_vocab:
                    if vocab_label.endswith(f"'d{value}"):
                        return self.label_to_idx[vocab_label]
            # Default to a constant
            return self.label_to_idx.get("'d0")
        
        # Handle operations
        op_mappings = {
            'add': 'plus',
            'plus': 'plus',
            'equal': 'eq',
            'equals': 'eq',
            'notequal': 'eq',
            'ne': 'eq',
            'ulnot': 'unot',
            'lnot': 'unot',
            'not': 'unot',
            'logor': 'lor',
            'logand': 'land',
            'bitand': 'and',
        }
        
        for op, vocab_op in op_mappings.items():
            if op in label_lower:
                return self.label_to_idx.get(vocab_op)
        
        # Handle signals/variables
        if 'state' in label_lower:
            return self.label_to_idx.get('state')
        if 'dout' in label_lower or 'out' in label_lower:
            return self.label_to_idx.get('dout')
        if 'reg' in label_lower or 'register' in label_lower:
            return self.label_to_idx.get('reg')
        if 'count' in label_lower:
            return self.label_to_idx.get('bitCountH')
        
        # Handle operators that might be in vocabulary
        if 'branch' in label_lower or 'if' in label_lower:
            return self.label_to_idx.get('branch')
        if 'concat' in label_lower or 'cat' in label_lower:
            return self.label_to_idx.get('concat')
        if 'select' in label_lower or 'part' in label_lower:
            return self.label_to_idx.get('partselect')
        if 'swap' in label_lower:
            return self.label_to_idx.get('SWAP')
        
        return None
    
    def get_graphs(self):
        return self.graphs
        
# ============================================================================


def verilog_to_graph_robust(verilog_file, graph_type="DFG", vocab_size=None, model_cfg=None):
    """
    Robust conversion of Verilog to graph
    
    Args:
        verilog_file: Path to .v or .sv file
        graph_type: "DFG" or "AST"
        vocab_size: Fixed vocabulary size (from model config)
        model_cfg: The model's config object (to set num_feature_dim on)
        
    Returns:
        Processed graph data and config
    """
    print(f"🔄 Converting {Path(verilog_file).name} to {graph_type} graph...")
    
    # Create temporary directory
    temp_dir = Path("/tmp/ht_robust") / f"test_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    design_dir = temp_dir / "design"
    
    try:
        # Prepare file (extract main module, rename to top)
        prepared_file = prepare_verilog_file(verilog_file, design_dir)
        
        # Generate graph
        if graph_type == "DFG":
            generator = RobustDFGGenerator()
        else:  # AST
            generator = RobustASTGenerator()
        
        hw_graph = generator.process(prepared_file)
        
        # Set graph metadata
        hw_graph.name = Path(verilog_file).stem
        hw_graph.type = "TjIn"  # Assume testing trojan files
        
        # Process graph with appropriate processor
        # CRITICAL: Use the model's config if provided, otherwise create new one
        if model_cfg is not None:
            cfg = model_cfg
            print(f"   🔗 Using model's config object")
        else:
            cfg = Config(graph_type=graph_type)
            print(f"   ⚠️  Creating new config (model_cfg not provided)")
        
        if vocab_size is not None:
            # Use fixed vocabulary processor for compatibility
            data_proc = FixedVocabDataProcessor(cfg, vocab_size=vocab_size)
        else:
            # Use original DataProcessor (for AST or when vocab_size unknown)
            data_proc = DataProcessor(cfg)
        
        data_proc.process(hw_graph)
        graphs = data_proc.get_graphs()
        
        print(f"   ✅ Graph generated ({len(hw_graph.nodes)} nodes, {len(hw_graph.edges)} edges)")
        
        return graphs, cfg
        
    finally:
        # Cleanup
        if temp_dir.exists():
            shutil.rmtree(temp_dir)


# ============================================================================
# Model Loading
# ============================================================================

def load_pretrained_model(model_type="DFG"):
    """Load pre-trained trojan detection model"""
    print(f"📥 Loading {model_type} pre-trained model...")
    
    # Model paths
    # NEW: Use newly trained models
    if model_type == "DFG":
        cfg_path = hw2vec_path / "trained_models" / "pretrained_DFG_TJ_RTL" / "model.cfg"
        pth_path = hw2vec_path / "trained_models" / "pretrained_DFG_TJ_RTL" / "model.pth"
    else:  # AST
        cfg_path = hw2vec_path / "trained_models" / "pretrained_AST_TJ_RTL" / "model.cfg"
        pth_path = hw2vec_path / "trained_models" / "pretrained_AST_TJ_RTL" / "model.pth"
    
    cfg = Config(graph_type=model_type)
    model = GRAPH2VEC(cfg)
    
    # Load configuration
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
    
    # Load weights
    model.load_state_dict(torch.load(pth_path, map_location='cpu'))
    model.to(cfg.device)
    model.eval()
    
    print(f"   ✅ {model_type} model loaded")
    return model, cfg


# ============================================================================
# Trojan Detection
# ============================================================================

def detect_trojan(verilog_file, model_type="DFG", model=None, cfg=None):
    """Detect hardware trojan in a Verilog design"""
    
    if model is None:
        model, cfg = load_pretrained_model(model_type)
    
    # Get vocab size from model type
    # For DFG: 37 features, for AST: varies
    vocab_size = 37 if model_type == "DFG" else None
    
    # CRITICAL FIX: Pass the model's config to the graph generation
    # This ensures num_feature_dim is set on the RIGHT config object
    graphs, graph_cfg = verilog_to_graph_robust(
        verilog_file, 
        model_type, 
        vocab_size=vocab_size,
        model_cfg=cfg  # Pass the model's config!
    )
    
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
    """Detect trojan using both DFG and AST models"""
    
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
    try:
        dfg_result = detect_trojan(verilog_file, "DFG", dfg_model, dfg_cfg)
    except Exception as e:
        print(f"   ❌ DFG failed: {e}")
        dfg_result = {"prediction": "ERROR", "confidence": -1.0, "prob_trojan": -1.0, "prob_clean": -1.0}

    # Test with AST
    print()
    try:
        ast_result = detect_trojan(verilog_file, "AST", ast_model, ast_cfg)
    except Exception as e:
        print(f"   ❌ AST failed: {e}")
        ast_result = {"prediction": "ERROR", "confidence": -1.0, "prob_trojan": -1.0, "prob_clean": -1.0}

    # Ensemble decision - handle errors
    if dfg_result['prediction'] == "ERROR" and ast_result['prediction'] == "ERROR":
        # Both failed
        ensemble_pred = "ERROR"
        ensemble_conf = -1.0
        avg_prob_trojan = -1.0
    elif dfg_result['prediction'] == "ERROR":
        # Only DFG failed, use AST result
        ensemble_pred = ast_result['prediction']
        ensemble_conf = ast_result['confidence']
        avg_prob_trojan = ast_result['prob_trojan']
    elif ast_result['prediction'] == "ERROR":
        # Only AST failed, use DFG result
        ensemble_pred = dfg_result['prediction']
        ensemble_conf = dfg_result['confidence']
        avg_prob_trojan = dfg_result['prob_trojan']
    else:
        # Both succeeded
        avg_prob_trojan = (dfg_result['prob_trojan'] + ast_result['prob_trojan']) / 2
        
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
            "avg_prob_trojan": avg_prob_trojan
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
    """Test all Verilog files in a directory"""
    
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
    
    verilog_files = list(set(verilog_files))
    
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
    
    # Summary
    if model_type == "ensemble":
        trojans_detected = sum(1 for r in results if r.get('ensemble', {}).get('prediction') == "TROJAN")
    else:
        trojans_detected = sum(1 for r in results if r.get('prediction') == "TROJAN")
    
    print(f"\n📊 SUMMARY:")
    print(f"   Total files: {len(results)}")
    print(f"   Trojans detected: {trojans_detected}")
    print(f"   Clean designs: {len(results) - trojans_detected}")
    
    return results


# ============================================================================
# CLI
# ============================================================================

def main():
    """Main CLI"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Robust Hardware Trojan Detection")
    parser.add_argument("input", help="Verilog file or directory")
    parser.add_argument("--model", choices=["DFG", "AST", "ensemble"], default="ensemble")
    parser.add_argument("--output", default="detection_results.json")
    
    args = parser.parse_args()
    input_path = Path(args.input)
    
    if input_path.is_file():
        if args.model == "ensemble":
            result = detect_trojan_ensemble(str(input_path))
        else:
            result = detect_trojan(str(input_path), args.model)
        
        with open(args.output, 'w') as f:
            json.dump(result, f, indent=2)
        
        print(f"\n💾 Result saved to: {args.output}")
    
    elif input_path.is_dir():
        test_directory(str(input_path), args.output, args.model)
    
    else:
        print(f"❌ Error: {input_path} not found")
        return 1
    
    return 0


if __name__ == "__main__":
    if len(sys.argv) == 1:
        print("🔬 Robust Hardware Trojan Detection Tool")
        print("=" * 50)
        print("\n📖 USAGE:")
        print("\n  python ht_testing_robust.py <file_or_directory>")
        print("\n📝 EXAMPLES:")
        print("\n  python ht_testing_robust.py RISCV_with_HT001.sv")
        print("  python ht_testing_robust.py trojan_files/ --output results.json")
        print()
    else:
        sys.exit(main())