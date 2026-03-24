import argparse
import sys
import random
randint = random.randint

parser = argparse.ArgumentParser(
        description='Generate random RV32 assembly. '
        'For this out-of-order core, use `--no-auipc -m` when targeting the RV32IM configuration.')
parser.add_argument('-n',
                    default = 500,
                    type = int,
                    help = 'how many instructions to generate, 500 by default')
parser.add_argument('-f',
                    default = 'randgen.s',
                    metavar = 'PATH',
                    help = 'file to write assembly to, randgen.s by default')
parser.add_argument('-z',
                    action = 'store_true',
                    help = 'disable hazard generation')
parser.add_argument('-l',
                    action = 'store_true',
                    help = 'enable load/store generation')
parser.add_argument('-r',
                    default = 32,
                    type = int,
                    help = 'number of registers to use, default 32')
parser.add_argument('-b',
                    action = 'store_true',
                    help = 'enable branch/jal/jalr generation')
parser.add_argument('-m',
                    action = 'store_true',
                    help = 'enable rv32m extension')
parser.add_argument('--no-auipc',
                    action = 'store_false',
                    dest = 'auipc',
                    help = 'disable auipc')
args = parser.parse_args()

ls_data_size = 16

# print(args)

f = open(args.f, 'w')

f.write('# generated with {}\n'.format(repr(' '.join(sys.argv))))
f.write('''.section .text
.globl _start
_start:
''')

# mapping from register to load/store instructions using those
# registers as addresses
ls_insns = {}

# iiii = 0
# iiij = 1
def reg():
    # global iiii, iiij
    # iiii += 1
    # if iiii == iiij:
        # iiii = 0
        # iiij += 1
    # return f'x{iiii}'
    res = f'x{randint(0,args.r-1)}'
    return res

def op_reg(name):
    def f():
        rd, rs1, rs2 = reg(), reg(), reg()
        return f'{name} {rd}, {rs1}, {rs2}', rd, [rs1, rs2]
    return f

def op_imm(name):
    def f():
        rd, rs1 = reg(), reg()
        return f'{name} {rd}, {rs1}, {randint(-2**11, 2**11-1)}', rd, [rs1]
    return f

def op_shifti(name):
    def f():
        rd, rs1 = reg(), reg()
        return f'{name} {rd}, {rs1}, {randint(0,31)}', rd, [rs1]
    return f

def op_lui(name):
    def f():
        rd = reg()
        return f'{name} {rd}, {randint(0, 2**20-1)}', rd, []
    return f

def op_ls_setup():
    rd = f'x{randint(1,args.r-1)}'
    typ = random.choice(['lw', 'lh', 'lhu', 'lb', 'lbu',
                         'sw', 'sh', 'sb'])
    align = ~({'w': 3, 'h': 1, 'b': 0}[typ[1]])
    offset = randint(0, ls_data_size*4-1) & align
    offset2 = randint(-2**11, 2**11-1)
    r2 = reg()
    ls_insns[rd] = (f'{typ} {r2}, {offset2}({rd})',
                    r2 if typ[0] == 'l' else None,
                    [r2, rd] if typ[0] == 's' else [rd])
    return (f'la {rd}, ls_data+({offset-offset2})', rd, [])

# this op allows for the hazard of a load/store address depending
# on a load, ie indirection
def op_sl_combo():
    rdata = f'x{randint(1,args.r-1)}'
    raddr = f'x{randint(1,args.r-1)}'
    return (f'sw {rdata}, ls_data, {raddr}\n'
            f'    lw {rdata}, ls_data', raddr, [])
    # we addtionally do write to rdata, so we can only use
    # this if hazards are supported. I couldd extend the api
    # to support returning three sets of registers per insn, ones
    # that are written to, ones that are modified, and
    # ones that are read. maybe later shrugs

def op_br(name):
    def f():
        rs1, rs2 = reg(), reg()
        return f'{name} {rs1}, {rs2}, .+16' + 3*'\n    nop', None, [rs1, rs2]
    return f

def op_jal():
    rd = reg()
    return f'jal {rd}, .+8' + '\n    nop', rd, []

def op_jalr():
    rd = f'x{randint(1,args.r-1)}'
    return (f'lui {rd}, %hi(.+16)\n'
            f'    jalr {rd}, {rd}, %lo(.+12)' + 2*'\n    nop', rd, [])

def genops(op_f, *names):
    return [op_f(n) for n in names]

ops = [
        *genops(op_reg, 'add', 'sub', 'sll', 'slt', 'sltu',
              'xor', 'srl', 'sra', 'or', 'and'),
        *genops(op_imm, 'addi', 'slti', 'sltiu',
              'xori', 'ori', 'andi'),
        *genops(op_shifti, 'slli', 'srli', 'srai'),
        *genops(op_lui, 'lui')
]
if args.l:
    ops += [op_ls_setup]*5
if args.l and not args.z:
    ops += [op_sl_combo]*3
if args.b:
    ops += genops(op_br, 'beq', 'bne', 'blt', 'bltu', 'bge', 'bgeu')
    ops += [op_jal, op_jalr]
if args.auipc:
    ops += [op_lui('auipc')]
if args.m:
    ops += genops(op_reg, 'mul', 'mulh', 'mulhsu', 'mulhu',
                  'div', 'divu', 'rem', 'remu')

for i in range(0,32):
    f.write(f'    li x{i}, {randint(0, 2**32-1)}\n')
f.write('\n')

prev_rds = []

for i in range(args.n):
    if len(ls_insns) > 0 and randint(0,10) == 0:
        op = None
        insn, rd, rss = random.choice(list(ls_insns.values()))
    else:
        op = random.choice(ops)
        insn, rd, rss = op()
    if insn == 'slti x0, x0, -256': continue # prevent early end of sim
    hazard = False
    for rs in rss:
        hazard = hazard or rs in prev_rds
    if rd != None:
        prev_rds.append(rd)
        if op is not op_ls_setup:
            ls_insns.pop(rd, None)
    prev_rds = prev_rds[-5:]
    if hazard and args.z:
        prev_rds = prev_rds[-1:]
        for i in range(5):
            f.write('    nop\n')
    f.write(f'    {insn}\n')

f.write('''
    nop
    nop
    nop
    nop
    nop
    slti x0, x0, -256 # end simulation
    nop
    nop
    nop
    nop
    nop
''')
if args.l:
    f.write('ls_data:\n')
    for i in range(ls_data_size):
        f.write(f'    .word {randint(0, 2**32-1)}\n')

f.close()
