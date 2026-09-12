#!/usr/bin/env python3
from pathlib import Path

p = Path("out/linux/src/arch/x86/kernel/cpu/common.c")
bak = Path("out/linux/src/arch/x86/kernel/cpu/common.c.bak-lfs")
if bak.exists():
    p.write_text(bak.read_text())

t = p.read_text()
old = (
    "\tfpu__init_system();\n"
    "\tfpu__init_cpu();\n"
    "\n"
    "\t/*\n"
    "\t * Ensure that access to the per CPU representation has the initial\n"
    "\t * boot CPU configuration.\n"
    "\t */\n"
    "\t*c = boot_cpu_data;\n"
    "\tc->initialized = true;\n"
    "\n"
    "\talternative_instructions();\n"
)
new = (
    "\tfpu__init_system();\n"
    '\tpr_info("lfs-boot: after fpu__init_system\\n");\n'
    "\tfpu__init_cpu();\n"
    '\tpr_info("lfs-boot: after fpu__init_cpu\\n");\n'
    "\n"
    "\t/*\n"
    "\t * Ensure that access to the per CPU representation has the initial\n"
    "\t * boot CPU configuration.\n"
    "\t */\n"
    "\t*c = boot_cpu_data;\n"
    "\tc->initialized = true;\n"
    "\n"
    '\tpr_info("lfs-boot: before alternative_instructions\\n");\n'
    "\talternative_instructions();\n"
    '\tpr_info("lfs-boot: after alternative_instructions\\n");\n'
)
if old not in t:
    raise SystemExit("pattern not found")
p.write_text(t.replace(old, new, 1))
print("patched OK")
for i, line in enumerate(p.read_text().splitlines(), 1):
    if "lfs-boot:" in line:
        print(f"{i}: {line}")
