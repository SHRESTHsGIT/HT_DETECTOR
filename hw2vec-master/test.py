import torch
import sys
import json
from pathlib import Path

# Add hw2vec to path (so imports work when running from anywhere)
sys.path.append(str(Path(__file__).resolve().parent))

from hw2vec.graph2vec.models import GRAPH2VEC

# ============================================
# Config object
# ============================================
class SimpleConfig:
    def __init__(self):
        self.device = "cpu"  # M2 Mac
        self.dropout = 0.5
        self.graph_type = "DFG"
        self.num_feature_dim = None

cfg = SimpleConfig()

# ============================================
# Absolute model paths (update verified paths)
# ============================================
BASE_DIR = Path("/Users/shresthshankhdhar/Documents/RESEARCH/HT_DES/hw2vec-master/assets")

DFG_DIR = BASE_DIR / "pretrained_DFG_TJ_RTL"
AST_DIR = BASE_DIR / "pretrained_AST_TJ_RTL"

cfg_path = DFG_DIR / "model.cfg"
pth_path = DFG_DIR / "model.pth"

print("🧪 Testing DFG Trojan Detection Model...")
print(f"   Device: {cfg.device}")
print(f"   Config path: {cfg_path}")
print(f"   Weights path: {pth_path}")

try:
    model = GRAPH2VEC(cfg)
    
    # Load DFG config JSON
    with open(cfg_path) as f:
        model_configuration = json.load(f)

    from hw2vec.graph2vec.models import GRAPH_CONV, GRAPH_POOL, GRAPH_READOUT
    import torch.nn as nn

    # Build model architecture
    convs = []
    for setting in model_configuration['convs']:
        graph_conv_type, in_channels, out_channels = setting
        convs.append(GRAPH_CONV(graph_conv_type, int(in_channels), int(out_channels)))
    model.set_graph_conv(convs)

    pool_type, pool_in_channels, pool_ratio = model_configuration['pool']
    model.set_graph_pool(GRAPH_POOL(pool_type, pool_in_channels, pool_ratio))

    model.set_graph_readout(GRAPH_READOUT(model_configuration['readout']))

    fc_in_channel, fc_out_channel = model_configuration['fc']
    model.set_output_layer(nn.Linear(fc_in_channel, fc_out_channel))

    # Load weights
    model.load_state_dict(torch.load(pth_path, map_location='cpu'))
    model.to(cfg.device)
    model.eval()

    print("\n✅ SUCCESS! DFG Model loaded")
    print(f"   PyTorch version: {torch.__version__}")
    print(f"   Model on device: {next(model.parameters()).device}")

    # ============================================
    # Test AST model
    # ============================================
    print("\n🧪 Testing AST Trojan Detection Model...")
    cfg.graph_type = "AST"

    ast_cfg_path = AST_DIR / "model.cfg"
    ast_pth_path = AST_DIR / "model.pth"

    ast_model = GRAPH2VEC(cfg)

    with open(ast_cfg_path) as f:
        ast_config = json.load(f)

    convs = []
    for setting in ast_config['convs']:
        graph_conv_type, in_channels, out_channels = setting
        convs.append(GRAPH_CONV(graph_conv_type, int(in_channels), int(out_channels)))
    ast_model.set_graph_conv(convs)

    pool_type, pool_in_channels, pool_ratio = ast_config['pool']
    ast_model.set_graph_pool(GRAPH_POOL(pool_type, pool_in_channels, pool_ratio))

    ast_model.set_graph_readout(GRAPH_READOUT(ast_config['readout']))

    fc_in_channel, fc_out_channel = ast_config['fc']
    ast_model.set_output_layer(nn.Linear(fc_in_channel, fc_out_channel))

    ast_model.load_state_dict(torch.load(ast_pth_path, map_location='cpu'))
    ast_model.to(cfg.device)
    ast_model.eval()

    print("✅ SUCCESS! AST Model loaded")

    print("\n" + "=" * 60)
    print("🎉 BOTH MODELS WORK WITH MODERN PYTORCH!")
    print("=" * 60)
    print("✅ DFG Model: Ready")
    print("✅ AST Model: Ready")
    print("✅ Device: CPU (M2 Mac)")
    print("✅ You can now run Trojan detection!")

except Exception as e:
    print(f"\n❌ FAILED: {e}")
    import traceback
    traceback.print_exc()
