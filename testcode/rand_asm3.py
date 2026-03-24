import argparse
import sys
import random
import collections as col
import functools
randint = random.randint

intp = functools.partial(int, base=0)

parser = argparse.ArgumentParser()
parser.add_argument('-n',
                    default = 500,
                    type = intp,
                    dest = 'num_insn',
                    help = 'how many instructions to generate, 500 by default')
parser.add_argument('-f',
                    default = 'randgen.s',
                    metavar = 'PATH',
                    dest = 'file',
                    help = 'file to write assembly to, randgen.s by default')
# args.z true when we need to generate nop's
parser.add_argument('-z',
                    action = 'store_false',
                    dest = 'en_hazards',
                    help = 'enable hazard generation')
parser.add_argument('-l',
                    nargs = '?',
                    type = intp,
                    const = 32,
                    default = 0,
                    metavar = 'words',
                    dest = 'load_words',
                    help = 'enable load/store generation with [words] (default 32) words')
parser.add_argument('-r',
                    default = 32,
                    type = intp,
                    dest = 'num_regs',
                    help = 'number of registers to use, default 32')
parser.add_argument('-p',
                    default = 0xaaaaa000,
                    type = intp,
                    dest = 'initial_pc',
                    help = 'initial program counter, default 0xaaaaa000')
parser.add_argument('-b',
                    action = 'store_true',
                    dest = 'en_branch',
                    help = 'enable branch/jal/jalr generation')
parser.add_argument('-t',
                    action = 'store_true',
                    dest = 'test',
                    help = 'test flag')
args = parser.parse_args()

# print(args)

f = open(args.f, 'w')

f.write('# generated with {}\n'.format(repr(' '.join(sys.argv))))
f.write('''.section .text
.globl _start
_start:
''')

def split_lui(v):
    up = v & 0xfffff000
    low = v & 0xfff
    if low >= 2**11:
        up  = up  + 2**11
        low = low - 2**11
    up = (up >> 12) & 0xfffff
    return up, low

pc = args.initial_pc
reg_state = [randint(0, 2**32-1) for i in range(32)]
for i in range(32):
    up, low = split_lui(reg_state[i])
    f.write(f'    lui x{i}, {up}\n'
            f'    addi x{i}, x{i}, {low}\n')
for i in range(5):
    f.write('    nop\n')
pc += (32*2 + 5)*4
load_addr = pc + (args.num_insn + 5 + 1 + 5)*4
initial_ls_data = [randint(0,2**32-1) for i in range(args.load_words)]
ls_data = initial_ls_data.copy()
insn_num = 0
insn_slots = [''] * args.num_insn
remaining_slots = {*range(args.num_insn)}
M = 2**32 # modulus

'''
# to ensure that we always have a way out when done,
# we set every 2**18-1 instructions starting at
# insn_num 2**18-1 to a jump to the following / the
# end
if args.en_branch:
    for i in range(2**18-1, args.num_insn, 2**18-1):
        remaining_slots.remove(i)
        if i + 2**18 - 1 >= args.num_insn:
            insn_slots[i] = 'j test_end'
        else: insn_slots[i] = f'j .+{2**20-4}'
'''

def rand_reg(start=0):
    return randint(start, args.num_regs)

def winsn(s, target):
    global insn_num
    assert 0 <= target <= args.num_insn
    assert (target == args.num_insn or
            not insn_slots[target])
    assert type(s) == str and s != ''
    insn_slots[insn_num] = s
    remaining_slots.remove(insn_num)
    insn_num = target

def winsn_nobr(s):
    winsn(s, insn_num+1)

def jump_targets(v, imm_bits):
    s = remaining_slots - {insn_num}
    # only jump to spaces with a two word gap,
    # that way we always are able to generate a
    # long jump if it's the only option
    s = s & {n-1 for n in s}
    #r = {((x-pc) % M) // 4 for x in range(v-2**(imm_bits-1),
                                          #v+2**(imm_bits-1))
         #if x % 4 == 0}
    s = {x for x in s if -2**(imm_bits-1) <=
         ((x*4 + pc - v + 2**31) % M) - 2**31 < 2**(imm_bits-1)}
    # r is the set of indexes in insn_slots we can
    # jump to by adding v to a signed immediate of imm_bits
    return s
def jump_targets_pcrel(imm_bits):
    return jump_targets(pc + 4*insn_num, imm_bits)

def pick_target(v, imm_bits):
    s = jump_targets(v, imm_bits)
    if len(s) == 0:
        return None
    # could make this more efficient with trees
    return random.choice(list(s))
def pick_target_pcrel(imm_bits):
    return pick_target(pc + 4*insn_num, imm_bits)

def check_cramped():
    global insn_num, remaining_slots
    # jal immediate, widest possible single insn jump
    s = jump_targets_pcrel(21)
    t = jump_targets_pcrel(32)
    if len(s) != 0 or (len(t) == 0 and insn_num >= args.num_insn-2):
        return True # not cramped
    assert {insn_num, insn_num+1} <= remaining_slots
    target = random.choice(t) if len(t) else args.num_insn
    addr = pc + 4*target
    up, low = split_lui(addr)
    reg = rand_reg(1)
    insn_slots[insn_num] = f'lui x{reg}, {up}'
    insn_slots[insn_num+1] = f'jalr x0, x{reg}, {low}'
    remaining_slots -= {insn_num, insn_num+1}
    insn_num = target
    reg_state[reg] = up << 12
    return False

while insn_num != args.num_insn:
    if check_cramped():
        random.choice(ops)()

f.write('''
test_end:
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
if args.load_words:
    f.write('ls_data:\n')
    for i in range(args.load_words):
        f.write(f'    .word {initial_ls_data[i]}\n')

f.close()
