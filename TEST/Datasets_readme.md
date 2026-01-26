# Hardware Security Dataset

This repository contains datasets for hardware security research, specifically focusing on Hardware Trojan Detection and IP Piracy Detection. The datasets are sourced from the hw2vec project available at [https://github.com/AICPS/hw2vec](https://github.com/AICPS/hw2vec).

## Dataset Overview

The dataset collection includes both toy datasets (for quick testing and learning) and references to full-scale datasets available through IEEE DataPort.

## Dataset Categories

### 1. Hardware Trojan Detection Datasets

Hardware trojans are malicious modifications inserted into hardware designs. These datasets help in developing and testing trojan detection methods.

#### TJ-RTL-toy (Toy Dataset)
- **Location**: `TJ-RTL-toy/`
- **Format**: Verilog RTL (Register Transfer Level) files
- **Structure**:
  - `TjFree/` - Contains clean, trojan-free hardware designs
  - `TjIn/` - Contains hardware designs with trojans inserted
- **Design Organization**: Each subfolder (e.g., `det_1011/`, `det_1012/`) represents an individual hardware design with its Verilog files (`.v`)

#### Full TJ Dataset
- **Source**: Trust-Hub trojan benchmark
- **Format**: DFG (Data Flow Graph)
- **Download**: [IEEE DataPort - Dataset 4618](http://ieee-dataport.org/4618)
- **Description**: Complete dataset converted to Data Flow Graph format for comprehensive trojan detection research

### 2. IP Piracy Detection Datasets

IP piracy involves unauthorized copying or modification of intellectual property in hardware designs. These datasets facilitate research in detecting such violations.

#### IP-RTL-toy (Toy Dataset - RTL Level)
- **Location**: `IP-RTL-toy/`
- **Format**: Verilog RTL files
- **Structure**: Contains pairs of hardware designs for piracy comparison analysis
- **Organization**: Each `design_pair_X/` folder contains Verilog files for comparison

#### IP-Netlist-toy (Toy Dataset - Gate Level)
- **Location**: `IP-Netlist-toy/`
- **Format**: Gate-level netlist Verilog files
- **Structure**: Contains pairs of gate-level hardware designs for piracy comparison
- **Organization**: Each `design_pair_X/` folder contains gate-level Verilog files

#### Full IP Dataset
- **Source**: Trust-Hub benchmark
- **Download**: [IEEE DataPort - Dataset 4618](http://ieee-dataport.org/4618)
- **Description**: Complete IP piracy detection dataset from the Trust-Hub benchmark

## Directory Structure

```
datasets.zip                           # Compressed archive of all datasets
├── TJ-RTL-toy/                       # Hardware Trojan Detection - RTL
│   ├── TjFree/                       # Trojan-free designs
│   │   ├── det_1011/
│   │   │   └── *.v                   # Verilog files
│   │   ├── det_1012/
│   │   │   └── *.v
│   │   └── ...
│   └── TjIn/                         # Trojan-infected designs
│       ├── det_1011/
│       │   └── *.v
│       ├── det_1012/
│       │   └── *.v
│       └── ...
├── IP-RTL-toy/                       # IP Piracy Detection - RTL
│   ├── design_pair_1/
│   │   └── *.v
│   ├── design_pair_2/
│   │   └── *.v
│   └── ...
└── IP-Netlist-toy/                   # IP Piracy Detection - Netlist
    ├── design_pair_1/
    │   └── *.v
    ├── design_pair_2/
    │   └── *.v
    └── ...
```

## File Formats

- **RTL (Register Transfer Level)**: High-level hardware description in Verilog
- **Netlist**: Gate-level hardware description showing interconnections between logic gates
- **DFG (Data Flow Graph)**: Graph-based representation of data flow in hardware designs

## Getting Started

1. **Extract the datasets**: Unzip `datasets.zip` to access the toy datasets
2. **Choose your research focus**:
   - For trojan detection: Use `TJ-RTL-toy/`
   - For IP piracy detection: Use `IP-RTL-toy/` or `IP-Netlist-toy/`
3. **Scale up**: Download the full datasets from IEEE DataPort for comprehensive research

## Use Cases

- **Hardware Trojan Detection**: Develop machine learning models to identify malicious modifications in hardware designs
- **IP Piracy Detection**: Create algorithms to detect unauthorized copying or modification of hardware IP
- **Hardware Security Research**: Study security vulnerabilities in hardware design workflows
- **Educational Purposes**: Learn about hardware security threats and detection methodologies

## Citations

If you use these datasets in your research, please cite the original hw2vec project and the Trust-Hub benchmark appropriately.

## Additional Resources

- **hw2vec GitHub Repository**: [https://github.com/AICPS/hw2vec](https://github.com/AICPS/hw2vec)
- **IEEE DataPort Full Datasets**: [http://ieee-dataport.org/4618](http://ieee-dataport.org/4618)
- **Trust-Hub**: The source benchmark for these security-focused hardware datasets

## License

Please refer to the original dataset sources for licensing information and usage restrictions.