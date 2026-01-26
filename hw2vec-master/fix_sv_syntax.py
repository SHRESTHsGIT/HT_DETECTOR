# Quick patch to handle SystemVerilog syntax
import re

script_path = "/Users/shresthshankhdhar/Documents/RESEARCH/HT_DES/hw2vec-master/ht_testing_robust.py"

with open(script_path, 'r') as f:
    content = f.read()

# Find the function and add SV-to-V conversion
old_func = '''    # Save as topModule.v
    output_file = output_dir / "topModule.v"
    with open(output_file, 'w') as f:
        f.write(module_code)'''

new_func = '''    # Convert SystemVerilog to Verilog
    # Remove 'int' type from localparams
    module_code = re.sub(r'localparam\s+int\s+', 'localparam ', module_code)
    # Remove 'logic' and replace with 'reg' or 'wire'
    module_code = re.sub(r'\\binput\s+logic\\b', 'input wire', module_code)
    module_code = re.sub(r'\\boutput\s+logic\\b', 'output reg', module_code)
    module_code = re.sub(r'\\blogic\\b', 'reg', module_code)
    # Remove typedef enum (convert to simple parameters)
    module_code = re.sub(r'typedef\s+enum.*?\\}\\s*\\w+;', '// enum removed', module_code, flags=re.DOTALL)
    
    # Save as topModule.v
    output_file = output_dir / "topModule.v"
    with open(output_file, 'w') as f:
        f.write(module_code)'''

if old_func in content:
    content = content.replace(old_func, new_func)
    with open(script_path, 'w') as f:
        f.write(content)
    print("✅ Patched ht_testing_robust.py")
    print("Now run your test again!")
else:
    print("⚠️ Could not find target code - trying alternative...")
    # Alternative: add the conversion right after module extraction
    if 'output_file = output_dir / "topModule.v"' in content:
        lines = content.split('\n')
        new_lines = []
        for i, line in enumerate(lines):
            new_lines.append(line)
            if 'original_name, module_code = extract_main_module(verilog_file)' in line:
                # Add conversion right after extraction
                indent = '    '
                new_lines.extend([
                    '',
                    indent + '# Convert SystemVerilog to Verilog',
                    indent + 'module_code = re.sub(r"localparam\\s+int\\s+", "localparam ", module_code)',
                    indent + 'module_code = re.sub(r"\\binput\\s+logic\\b", "input wire", module_code)',
                    indent + 'module_code = re.sub(r"\\boutput\\s+logic\\b", "output reg", module_code)',
                    indent + 'module_code = re.sub(r"\\blogic\\b", "reg", module_code)',
                    indent + 'module_code = re.sub(r"typedef\\s+enum.*?\\}\\s*\\w+;", "// enum removed", module_code, flags=re.DOTALL)',
                ])
        
        with open(script_path, 'w') as f:
            f.write('\n'.join(new_lines))
        print("✅ Alternative patch applied!")
        print("Now run your test again!")
