import os
import sys

# Find torch_geometric path
for path in sys.path:
    pyg_path = os.path.join(path, 'torch_geometric')
    if os.path.exists(pyg_path):
        print(f"Found torch_geometric at: {pyg_path}")
        
        # Fix dataloader.py
        dataloader_file = os.path.join(pyg_path, 'data', 'dataloader.py')
        
        if os.path.exists(dataloader_file):
            print(f"Patching: {dataloader_file}")
            
            # Read file
            with open(dataloader_file, 'r') as f:
                content = f.read()
            
            # Replace problematic import
            old_line = "from torch._six import container_abcs, string_classes, int_classes"
            new_lines = """import collections.abc as container_abcs
string_classes = str
int_classes = int"""
            
            if old_line in content:
                content = content.replace(old_line, new_lines)
                
                # Write back
                with open(dataloader_file, 'w') as f:
                    f.write(content)
                
                print("✅ Patch applied successfully!")
                print("\nNow run: python test.py")
                break
            else:
                print("⚠️ Line already patched or different")
                break
        else:
            print(f"❌ dataloader.py not found at {dataloader_file}")
    else:
        continue
else:
    print("❌ torch_geometric not found in sys.path")