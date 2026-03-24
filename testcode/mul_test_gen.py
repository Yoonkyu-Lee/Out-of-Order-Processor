f = open('mul_test.s', 'w')

f.write('''\
mul_test.s:
.align 4
.section .text
.globl _start
    # This program will provide a test for
    # all rv32m edge cases

_start:

# initialize
li x1, 1234
li x2, -1
li x3, 0x80000000
li x4, 0x7fffffff
li x5, -7654
li x6, 1
li x7, 0

nop
nop
nop
nop
nop
nop

''')

n_regs = 7

for insn in ['mul', 'mulh', 'mulhsu', 'mulhu',
             'div', 'divu', 'rem', 'remu']:
    for rs1 in range(1, n_regs+1):
        for rs2 in range(1, n_regs+1):
            f.write(f'{insn} x31, x{rs1}, x{rs2}\n')

f.write('''\

halt:
    slti x0, x0, -256
''')

f.close()

print(f'generated {8*n_regs*n_regs} instructions')
