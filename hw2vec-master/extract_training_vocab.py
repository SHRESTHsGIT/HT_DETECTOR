#!/usr/bin/env python3
"""
Extract vocabulary from TJ-RTL-toy dataset
"""
import sys
from pathlib import Path
from collections import Counter

sys.path.append(str(Path(__file__).parent))

from hw2vec.hw2graph import HW2GRAPH, DataProcessor
from hw2vec.config import Config

# Simple config
class SimpleConfig:
    def __init__(self):
        self.graph_type = "DFG"
        self.device = "cpu"
        self.dropout = 0.5
        self.raw_dataset_path = Path("assets/TJ-RTL-toy")

print("="*70)
print("EXTRACTING TRAINING VOCABULARY")
print("="*70)

cfg = SimpleConfig()
print(f"Dataset: {cfg.raw_dataset_path}")
print()

# Process graphs
hw2graph = HW2GRAPH(cfg)
nx_graphs = []

folders = list(hw2graph.find_hw_project_folders())
print(f"Found {len(folders)} designs\n")

for idx, hw_path in enumerate(folders, 1):
    print(f"[{idx}/{len(folders)}] {hw_path.name}...", end=" ")
    try:
        graph = hw2graph.code2graph(hw_path)
        nx_graphs.append(graph)
        print("✓")
    except Exception as e:
        print(f"✗ ({e})")

print(f"\nProcessed {len(nx_graphs)} graphs successfully\n")

# Extract vocabulary
data_proc = DataProcessor(cfg)
for graph in nx_graphs:
    data_proc.process(graph)

vocab_size = data_proc.num_node_labels
print("="*70)
print(f"VOCABULARY SIZE: {vocab_size}")
print("="*70)

# Count all labels
all_labels = Counter()
for graph in nx_graphs:
    for _, node_data in graph.nodes(data=True):
        if 'label' in node_data:
            all_labels[node_data['label']] += 1

vocabulary = [label for label, _ in all_labels.most_common()]

print(f"\nAll {len(vocabulary)} node types:")
for i, (label, count) in enumerate(all_labels.most_common(), 1):
    print(f"{i:3d}. {label:20s} ({count:5d} occurrences)")

# Save vocabulary
with open("training_vocabulary.py", "w") as f:
    f.write(f"# Training vocabulary (size={vocab_size})\n")
    f.write(f"VOCAB_SIZE = {vocab_size}\n")
    f.write(f"VOCABULARY = [\n")
    for label in vocabulary[:vocab_size]:
        f.write(f"    '{label}',\n")
    f.write("]\n")

print(f"\n✅ Saved to training_vocabulary.py")
print(f"   Vocabulary size: {vocab_size}")