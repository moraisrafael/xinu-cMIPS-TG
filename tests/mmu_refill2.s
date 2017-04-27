	##
	## Cause a TLB miss on a LOAD, then copy a mapping from page table
	##   cause a second miss by overwriting TLB[7] which maps ROM
	##
	## faulting LOAD is on a branch delay slot
	##
	## EntryHi     : EntryLo0           : EntryLo1
	## VPN2 g ASID : PPN0 ccc0 d0 v0 g0 : PPN1 ccc1 d1 v1 g1

	.include "cMIPS.s"

        # New entries cannot overwrite tlb[0,1] which map base of ROM, I/O

        # EntryHi cannot have an ASID different from zero, otw TLB misses
        .set entryHi_1,  0x00012000 #                 pfn0  zzcc cdvg
        .set entryLo0_1, 0x0000091b #  x0 x0 x0 x0 x0 1001  0001 1011 x91b
        .set entryLo1_1, 0x00000c1b #  x0 x0 x0 x0 x0 1100  0001 1011 xc1b

        .set entryHi_2,  0x00014000 #                 pfn0  zzcc cdvg
        .set entryLo0_2, 0x00001016 #  x0 x0 x0 x0 x1 0000  0001 0110 x1016
        .set entryLo1_2, 0x0000141e #  x0 x0 x0 x0 x1 0100  0001 1110 x141e

        .set entryHi_3,  0x00016000 #                 pfn0  zzcc cdvg
        .set entryLo0_3, 0x0000191f #  x0 x0 x0 x0 x1 1001  0001 1111 x191f
        .set entryLo1_3, 0x00001d3f #  x0 x0 x0 x0 x1 1101  0011 1111 x1d3f

        .set entryHi_4,  0x00018000 #                 pfn0  zzcc cdvg
        .set entryLo0_4, 0x00000012 #  x0 x0 x0 x0 x0 0000  0001 0010 x12
        .set entryLo1_4, 0x00000412 #  x0 x0 x0 x0 x0 0100  0001 0010 x412

	.set MMU_WIRED,  2  ### do not change mapping for ROM-0, I/O
	
	.text
	.align 2
	.set noreorder
	.set noat
	.org x_INST_BASE_ADDR,0
	.globl _start, _exit
	.ent _start

	## set STATUS, cop0, no interrupts enabled, kernel mode
_start:	li   $k0, 0x10000000
        mtc0 $k0, cop0_STATUS

	li   $k0, MMU_WIRED
	mtc0 $k0, cop0_Wired

	j main
	nop
	.end _start
	
	##
        ##================================================================
        ## exception vector_0000 TLBrefill, from See MIPS Run pg 145
        ##
        .org x_EXCEPTION_0000,0
        .ent _excp
        .set noreorder
        .set noat

_excp:  mfc0 $k1, cop0_Context
        lw   $k0, 0($k1)           # k0 <- TP[Context.lo]
        lw   $k1, 8($k1)           # k1 <- TP[Context.hi]
        mtc0 $k0, cop0_EntryLo0    # EntryLo0 <- k0 = even element
        mtc0 $k1, cop0_EntryLo1    # EntryLo1 <- k1 = odd element
	##
	## cause, on purpose, another miss on 2nd ROM mapping
	##
	li   $k0, 2
	mtc0 $k0, cop0_Index
	ehb
        tlbwi                      # update TLB
	
	li   $30, 'h'
	sw   $30, x_IO_ADDR_RANGE($20)	
	li   $30, 'e'
	sw   $30, x_IO_ADDR_RANGE($20)	
	li   $30, 'r'
	sw   $30, x_IO_ADDR_RANGE($20)	
	li   $30, 'e'
	sw   $30, x_IO_ADDR_RANGE($20)
	li   $30, '\n'
	sw   $30, x_IO_ADDR_RANGE($20)
	mfc0 $k1, cop0_CAUSE		# clear CAUSE

	eret
        .end _excp

        .org x_EXCEPTION_0100,0
_excp_0100:
        la   $k0, x_IO_BASE_ADDR
        mfc0 $k1, cop0_CAUSE
        sw   $k1, 0($k0)        # print CAUSE, flush pipe and stop simulation
        nop
        nop
        nop
        wait 0x02
        nop
        .org x_EXCEPTION_0180,0
_excp_0180:
        la   $k0, x_IO_BASE_ADDR
        mfc0 $k1, cop0_CAUSE
        sw   $k1, 0($k0)        # print CAUSE, flush pipe and stop simulation
        nop
        nop
        nop
        wait 0x02
        nop
_excp_0200:
        la   $k0, x_IO_BASE_ADDR
        mfc0 $k1, cop0_CAUSE
        sw   $k1, 0($k0)        # print CAUSE, flush pipe and stop simulation
        nop
        nop
        nop
        wait 0x03
        nop
        .org x_EXCEPTION_BFC0,0
_excp_BFC0:
        la   $k0, x_IO_BASE_ADDR
        mfc0 $k1, cop0_CAUSE
        sw   $k1, 0($k0)        # print CAUSE, flush pipe and stop simulation
        nop
        nop
        nop
        wait 0x04
        nop



	##
        ##================================================================
        ## normal code starts here
	##
        .org x_ENTRY_POINT,0

	
	## dirty trick: there is not enough memory for a full PT, thus
	##   we set the PT at the bottom of RAM addresses and have
	##   Context pointing into that address range

	.set PTbase, x_DATA_BASE_ADDR
	.ent main
main:	la   $20, x_IO_BASE_ADDR
	
	##
	## setup a PageTable
	##
	## 16 bytes per entry:  
	## EntryLo0                     : EntryLo1
	## PPN0 ccc0 d0 v0 g0 0000.0000 : PPN1 ccc1 d1 v1 g1 0000.0000
	##

	# load Context with PTbase
	la   $4, PTbase
	mtc0 $4, cop0_Context
	
	# 1st entry: PPN0 & PPN1 ROM
	li   $5, 0            # 1st ROM mapping
	mtc0 $5, cop0_Index
	nop
	tlbr

	mfc0 $6, cop0_EntryLo0
	# sw   $6, 0($20)
	mfc0 $7, cop0_EntryLo1
	# sw   $7, 0($20)

	sw  $6, 0x0($4)
	sw  $0, 0x4($4)
	sw  $7, 0x8($4)
	sw  $0, 0xc($4)

	
	# 2nd entry: PPN2 & PPN3 ROM
	li $5, 2              # 2nd ROM mapping
	mtc0 $5, cop0_Index
	nop
	tlbr

	mfc0 $6, cop0_EntryLo0
	# sw   $6, 0($20)
	mfc0 $7, cop0_EntryLo1
	# sw   $7, 0($20)


	sw  $6, 0x10($4)
	sw  $0, 0x14($4)
	sw  $7, 0x18($4)
	sw  $0, 0x1c($4)


	# 1024th entry: PPN6 & PPN7 RAM
	li   $5, 7           # 3rd RAM mapping
	mtc0 $5, cop0_Index
	nop
	tlbr

	mfc0 $6, cop0_EntryLo0
	# sw   $6, 0($20)
	mfc0 $7, cop0_EntryLo1
	# sw   $7, 0($20)

	.set ram6_displ,((x_DATA_BASE_ADDR + 6*4096)>>(13-4)) # num(VPN2)*16

	# li $1, ram6_displ
	# sw $1, 0($20)
	
	sw  $6, ram6_displ+0($4)
	sw  $0, ram6_displ+4($4)
	sw  $7, ram6_displ+8($4)
	sw  $0, ram6_displ+12($4)
	
	
	## change mapping for 3rd RAM TLB entry, thus causing a miss
chnge3:	li   $5, 7           # 3rd RAM mapping
	mtc0 $5, cop0_Index

	li   $9, 0x8000
	sll  $9, $9, 8

	mfc0 $8, cop0_EntryHi
	add  $8, $9, $8     # change tag
	mtc0 $8, cop0_EntryHi

	tlbwi		    # and write it back to TLB (Index = 6)

	nop
	nop
	nop
	
	##
	## cause miss on the load in the delay slot - miss on 6th RAM page
	##   then a second miss since handler (purposefully) updates the
	##   TLB entry for the 2nd ROM page
	##
	li  $15, (x_DATA_BASE_ADDR + 6*4096) # VPN2
		
last:	jal there
	lw  $16, 0($15)

	##
	## try to catch error in EPC.  Return address adjusted below
	##
	li   $30, '@'
	sw   $30, x_IO_ADDR_RANGE($20)
	sw   $30, x_IO_ADDR_RANGE($20)
	sw   $30, x_IO_ADDR_RANGE($20)
	li   $30, '\n'
	sw   $30, x_IO_ADDR_RANGE($20)
	
	
goBack:	li   $30, 'a'
	sw   $30, x_IO_ADDR_RANGE($20)
	li   $30, 'n'
	sw   $30, x_IO_ADDR_RANGE($20)
	li   $30, 'd'
	sw   $30, x_IO_ADDR_RANGE($20)
	li   $30, ' '
	sw   $30, x_IO_ADDR_RANGE($20)
	li   $30, 'b'
	sw   $30, x_IO_ADDR_RANGE($20)
	li   $30, 'a'
	sw   $30, x_IO_ADDR_RANGE($20)
	li   $30, 'c'
	sw   $30, x_IO_ADDR_RANGE($20)
	li   $30, 'k'
	sw   $30, x_IO_ADDR_RANGE($20)
	li   $30, ' '
	sw   $30, x_IO_ADDR_RANGE($20)
	li   $30, 'a'
	sw   $30, x_IO_ADDR_RANGE($20)
	li   $30, 'g'
	sw   $30, x_IO_ADDR_RANGE($20)
	li   $30, 'a'
	sw   $30, x_IO_ADDR_RANGE($20)
	li   $30, 'i'
	sw   $30, x_IO_ADDR_RANGE($20)
	li   $30, 'n'
	sw   $30, x_IO_ADDR_RANGE($20)
	li   $30, '\n'
	sw   $30, x_IO_ADDR_RANGE($20)
	sw   $30, x_IO_ADDR_RANGE($20)

	
	nop
	nop
        nop
	nop
	nop
        nop
        wait
	nop
	nop

	
	.org (x_INST_BASE_ADDR + 2*4096), 0

there:	li   $30, 't'
	sw   $30, x_IO_ADDR_RANGE($20)
	li   $30, 'h'
	sw   $30, x_IO_ADDR_RANGE($20)
	li   $30, 'e'
	sw   $30, x_IO_ADDR_RANGE($20)
	li   $30, 'r'
	sw   $30, x_IO_ADDR_RANGE($20)
	li   $30, 'e'
	sw   $30, x_IO_ADDR_RANGE($20)
	li   $30, '\n'
	sw   $30, x_IO_ADDR_RANGE($20)

	##
	## adjust return address to catch error in EPC
	##
	la   $31, goBack
	jr   $31
	nop
	
	
_exit:	nop
	nop
        nop
	nop
	nop
        nop
        wait
	nop
	nop
	.end main

