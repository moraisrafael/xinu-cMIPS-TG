/*  start.S  _start, memzero */

/************************************************************************/
/*									*/
/*   External symbol start (_start in assembly language) gives the	*/
/* location where execution begins after the bootstrap loader has	*/
/* placed a Xinu image in memory and is ready to execute the image.	*/
/*									*/
/*   After initializing the hardware and establishing a run-time	*/
/* environment suitable for C (including a valid stack pointer), the	*/
/* code jumps to the C function nulluser.				*/
/*									*/
/************************************************************************/


#include <interrupt.h>
#include <mips.h>

#include "cMIPS.s"


#define NULLSTK      8192       /* Safe size for NULLSTK */

.extern	flash_size

.text
	.align	4
	.globl	_minheap
	.globl	_start

/*------------------------------------------------------------------------
 *
 * _start   - set up interrupts, initialize the stack pointer, clear the
 *            null process stack, zero the BSS (uninitialized data)
 *            segment, and invoke nulluser
 *
 *------------------------------------------------------------------------
 */
	.ent _start
_start:

		# get physical page number for 2 pages at the bottom of RAM, for .data
		#  needed so simulations without a page table will not break
		#  read TLB[4] and write it to TLB[2]
		li    k0, 4
		mtc0  k0, c0_index
		ehb
		tlbr
		li    k1, 2
		mtc0  k1, c0_index
		ehb
		tlbwi

	/* Pick up flash size from a3 (where the boot loader leaves it)	*/

	# sw	a3, flash_size
	sw	zero, flash_size(zero)

	/* Clear Xinu-defined trap and interrupt vectors */
	// these are not used, there is no memory allocated to vectors
	# la	a0, IRQ_ADDR      ## invalid addresses for cMIPS
	# la	a1, IRQVEC_END
	# jal	memzero
	# la	a0, TRAPVEC_ADDR
	# la	a1, IRQVEC_END
	# jal	memzero

	
	/* Copy low-level interrupt dispatcher to reserved location.	*
	// these are not used, there is no memory allocated to vectors
	# la	a0, IRQ_ADDR		/* Reserved vector location	*/
	# la	a1, intdispatch		/* Start of dispatch code	*/
	# lw	v0, 0(a1)
	# sw	v0, 0(a0)		/* Store jump opcode		*/

	/* Clear interrupt related registers in the coprocessor */

        # STATUS: cop0, no interrupts enabled, kern mode
        li      k0, 0x1000f000
	mtc0	k0, CP0_STATUS		/* Clear interrupt masks	*/

	# COUNTER disabled, separate interr vector
	li      k0, 0x08800000
	mtc0	k0, CP0_CAUSE		/* Clear interrupt cause reg.	*/

	/* Clear and invalidate the L1 instruction and data caches */

	# jal	flushcache
		
	/* Set up Stack segment (see function summary) */

	li	s0, NULLSTK		/* Stack is NULLSTK bytes	*/
	la	a0, _end
	addu	s0, s0, a0		/* Top of stack = _end+NULLSTK	*/

	/* Word align the top of the stack */

	subu	s1, s0, 1
	srl	s1, 4
	sll	s1, 4
	
	/* Initialize the stack and frame pointers */

	move	sp, s1
	move	fp, s1
	
	/* Zero NULLSTK space below new stack pointer */

	la	a0, _end
	move	a1, s0
	# jal	memzero

	/* Clear the BSS segment */

	la	a0, _bss
	la	a1, _end
	# jal	memzero

	/* Store bottom of the heap */

	la	t0, minheap
	sw	s0, 0(t0)

	la      k0, _PT
	mtc0    k0, c0_context

        # STATUS: cop0, hw interrupt IRQ7,IRQ6,IRQ5,IRQ4 enabled, user mode
        li      k0, 0x1000f011
	mtc0	k0, c0_status		/* Clear interrupt masks	*/

	# enable COUNTER, separate interr vector
	li      k0, 0x00800000
	mtc0	k0, c0_cause		/* Clear interrupt cause reg.	*/
	
	j	nulluser	/* jump to the null process code */
	.end	_start

/*------------------------------------------------------------------------
 * memzero - clear a specified area of memory
 *
 * 	args are: starting address and ending address
 *------------------------------------------------------------------------
 */
	.ent	memzero
memzero:
	sw	zero, 0(a0)
	addiu	a0, a0, 4
	blt	a0, a1, memzero
	jr	ra
	.end	memzero


	## code from cMIPS/include/start.s
	##================================================================
	## exception vector_0000 TLBrefill, from See MIPS Run pg 145
	##
	.org x_EXCEPTION_0000,0
	.ent _excp_0000
_excp_0000:
	.set noreorder
	.set noat

	mfc0 k1, c0_context
	lw   k0, 0(k1)      	# k0 <- TP[context.lo]
	lw   k1, 8(k1)        # k1 <- TP[context.hi]
	mtc0 k0, c0_entrylo0   # EntryLo0 <- k0 = even element
	mtc0 k1, c0_entrylo1   # EntryLo1 <- k1 = odd element
	ehb
	tlbwr	                # update TLB
	eret	
	.end _excp_0000


        ##
        ##================================================================
        ## exception vector_0100 Cache Error (hw not implemented)
        ##
        .org x_EXCEPTION_0100,0
        .ent _excp_0100
_excp_0100:
        .set noreorder
        .set noat

        la   k0, x_IO_BASE_ADDR
        mfc0 k1, c0_cause
        sw   k1, 0(k0)        # print CAUSE, flush pipe and stop simulation
        nop
        nop
        nop
        wait 0x01
        nop
        .end _excp_0100


	##
	##================================================================
	## handler for all exceptions except interrupts and TLBrefill
	##
	## area to save up to 16 registers
        .bss
        .align  2
	.global _excp_0180ret
        .comm   _excp_saves 16*4
        # _excp_saves[0]=CAUSE, [1]=STATUS, [2]=ASID,
	#            [8]=$ra, [9]=$a0, [10]=$a1, [11]=$a2, [12]=$a3
	#            [13]=$sp [14]=$fp [15]=$at 
        .text
        .set noreorder
	.set noat
	
	.org x_EXCEPTION_0180,0  # exception vector_180
	.ent _excp_0180
_excp_0180:
	mfc0 k0, c0_status
	lui  k1, %hi(_excp_saves)
	ori  k1, k1, %lo(_excp_saves)
	sw   k0, 1*4(k1)
        mfc0 k0, c0_cause
	sw   k0, 0*4(k1)
	
	andi k0, k0, 0x3c    # keep only the first 16 ExceptionCodes & b"00"
	sll  k0, k0, 1       # displacement in vector with 8 bytes/element
	lui  k1, %hi(excp_tbl)
        ori  k1, k1, %lo(excp_tbl)
	add  k1, k1, k0
	nop
	jr   k1
	nop

excp_tbl: # see Table 8-25, pg 95,96
	wait 0x02  # interrupt, should never get here, abort simulation
	nop

	j handle_Mod  # 1
	nop

	j handle_TLBL # 2
	nop

	j handle_TLBL # 3 == TLBS if miss on PT, on the TLB, on a store
	nop		# should mark page as Modified on PT

	j excp_report # 4 AdEL addr error     -- abort simulation
	nop
	j excp_report # 5 AdES addr error     -- abort simulation
	nop
	j excp_report # 6 IBE addr error      -- abort simulation
	nop
	j excp_report # 7 DBE addr error      -- abort simulation
	nop
	
	wait 0x08 # j h_syscall # 8        -- abort simulation
	nop
	wait 0x09 # j h_breakpoint # 9     -- abort simulation
	nop
	wait 0x0a # j h_RI    # 10 reserved instruction -- abort simulation
	nop
	wait 0x0b # j h_CpU   # 11 coprocessor unusable -- abort simulation
	nop
	wait 0x0c # j h_Ov    # 12 overflow             -- abort simulation
	nop
	wait 0x0d # 13 trap                             -- abort simulation
	nop
	wait 0x0e # reserved, should never get here     -- abort simulation
	nop
	wait 0x0f # FP exception, should never get here -- abort simulation
	nop

h_TLBS:	
h_syscall:
h_breakpoint:
h_RI:
h_CpU:
h_Ov:

_excp_0180ret:
	lui  k1, %hi(_excp_saves) # Read previous contents of STATUS
	ori  k1, k1, %lo(_excp_saves)
	lw   k0, 1*4(k1)
        nop                        #  and do not modify its contents
	ori  k0, k0, M_StatusIEn #  and keep user/kernel mode
	mtc0 k0, c0_status	   #  but enable all interrupts
	ehb
	eret			   # Return from exception

	.end _excp_0180
	#----------------------------------------------------------------



	##
        ##===============================================================
        ## interrupt handlers at exception vector 0200
        ##
        # declare all handlers here, these must be in file handlers.s
        .extern countCompare  # IRQ7 = hwIRQ5, Cop0 counter
        .extern ttyInterrupt  # IRQ6 - hwIRQ4, see vhdl/tb_cMIPS.vhd
        .extern extCounter    # IRQ5 - hwIRQ3, see vhdl/tb_cMIPS.vhd

	.extern clkhandler
	
        .set M_CauseIM,0x0000ff00   # keep bits 15..8 -> IM = IP
        .set M_StatusIEn,0x0000f311 # user mode, enable irq7..4,irq1,irq0

        .set noreorder

        .org x_EXCEPTION_0200,0     # exception vector_200, interrupt handlers
        .ent _excp_0200
excp_0200:
_excp_0200:

	# copied from intdispatch.S
	
save:	addiu   sp, sp, -IRQREC_SIZE    /* Allocate space on stack      */
        mfc0    k1, CP0_EPC             /* Save interrupted PC value    */
        sw      AT, IRQREC_AT(sp)       /* Save assembler temp reg first*/
	sw      k1, IRQREC_EPC(sp)
        .set at
        # .set reorder
        sw      v0, IRQREC_V0(sp)       /* Save all general purpose regs*/
        sw      v1, IRQREC_V1(sp)
        sw      a0, IRQREC_A0(sp)
        sw      a1, IRQREC_A1(sp)
        sw      a2, IRQREC_A2(sp)
        sw      a3, IRQREC_A3(sp)
	sw      t0, IRQREC_T0(sp)
        sw      t1, IRQREC_T1(sp)
        sw      t2, IRQREC_T2(sp)
        sw      t3, IRQREC_T3(sp)
        sw      t4, IRQREC_T4(sp)
        sw      t5, IRQREC_T5(sp)
        sw      t6, IRQREC_T6(sp)
        sw      t7, IRQREC_T7(sp)
        sw      s0, IRQREC_S0(sp)
        sw      s1, IRQREC_S1(sp)
        sw      s2, IRQREC_S2(sp)
        sw      s3, IRQREC_S3(sp)
        sw      s4, IRQREC_S4(sp)
        sw      s5, IRQREC_S5(sp)
        sw      s6, IRQREC_S6(sp)
        sw      s7, IRQREC_S7(sp)
        sw      t8, IRQREC_T8(sp)
        sw      t9, IRQREC_T9(sp)
        sw      k0, IRQREC_K0(sp)
        sw      k1, IRQREC_K1(sp)
        sw      gp, IRQREC_S8(sp)
        sw      sp, IRQREC_SP(sp)
        sw      fp, IRQREC_S9(sp)
        sw      ra, IRQREC_RA(sp)
        # sw      zero, IRQREC_ZER(sp)
        mfhi    t0                      /* Save hi and lo               */
        mflo    t1
        sw      t0, IRQREC_HI(sp)
        sw      t1, IRQREC_LO(sp)

	mfc0    k0, c0_cause		/* save CAUSE and STATUS	*/
        mfc0    k1, c0_status
	sw      k0, IRQREC_CAUSE(sp)
        sw      k1, IRQREC_STATUS(sp)

	.set noreorder
dispatch:
	andi k0, k0, M_CauseIM   # Keep only IP bits from Cause
        and  k0, k0, k1          # and mask with STATUS's IM bits 
        srl  k0, k0, 10          # keep only 3 MS bits of IP (irq7..5)
        lui  k1, %hi(handlers_tbl) # plus displacement in j-table of 8 bytes
        ori  k1, k1, %lo(handlers_tbl)
        add  k1, k1, k0
	nop
        jr   k1
	nop
	
	## the code for each handler must contain an exception return (eret)
handlers_tbl:
        j dismiss                  # no request: 000
        nop

        j extCounter               # lowest priority, IRQ4: 0001
        nop

        nop #j DMAinterr                # mid priority, IRQ5: 001x
        nop
        nop #j DMAinterr
        nop
	
        j uart                     # mid priority, IRQ6: 01xx
        nop
        j uart
        nop
        j uart
        nop
        j uart
        nop

        j clk             # highest priority, IRQ7: 1xxx
        nop
        j clk
        nop
        j clk
        nop
        j clk
        nop
        j clk
        nop
        j clk
        nop
        j clk
        nop
        j clk
        nop


	##
	## code replicated from system/dispatch.c
	##
	# mask = disable();	/* Disable interrupts for duration */
uart:	addiu   sp, sp, -8	# make room in stack
        mfc0    v0, CP0_STATUS
        li      a0, ~STATUS_IE
        and     a1, v0, a0
	sw      v0, 4(sp)	# and save STATUS there
	
	# exlreset();		/* Reset system-wide exception bit */
	li      a2, ~STATUS_EXL
        and     v0, a1, a2
	mtc0    a1, CP0_STATUS
	
	# (*handler) ();	/* Invoke device-specific handler  */
	jal ttyInterrupt
	nop
	
	# exlset();		/* Set system-wide exception bit   */
	# restore(mask);
	lw      v0, 4(sp)	# recover saved STATUS
	addiu   sp, sp, 8
        li      a2, STATUS_EXL
        or      v0, v0, a2
        mtc0    v0, CP0_STATUS
	j   _restore
	nop
	

	# mask = disable();	/* Disable interrupts for duration */
clk:	addiu   sp, sp, -8	# make room in stack
        mfc0    v0, CP0_STATUS
        li      a0, ~STATUS_IE
        and     a1, v0, a0
	sw      v0, 4(sp)	# and save STATUS there
	
	# exlreset();		/* Reset system-wide exception bit */
	li      a2, ~STATUS_EXL
        and     v0, a1, a2
	mtc0    a1, CP0_STATUS
	
	# (*handler) ();	/* Invoke device-specific handler  */
	jal clkhandler		  # clk handler MUST return to this address
	nop

	# exlset();		/* Set system-wide exception bit   */
	# restore(mask);
	lw      v0, 4(sp)	# recover saved STATUS
	addiu   sp, sp, 8
        li      a2, STATUS_EXL
        or      v0, v0, a2
        mtc0    v0, CP0_STATUS
	# j   _restore
	# nop
	
_restore:
        lw      t0, IRQREC_HI(sp)       /*  restore all state           */
        lw      t1, IRQREC_LO(sp)
        mthi    t0
        mtlo    t1
        lw      ra, IRQREC_RA(sp)       /* Restore general purpose regs */
        lw      fp, IRQREC_S9(sp)
        lw      gp, IRQREC_S8(sp)
        lw      t9, IRQREC_T9(sp)
        lw      t8, IRQREC_T8(sp)
        lw      s7, IRQREC_S7(sp)
        lw      s6, IRQREC_S6(sp)
        lw      s5, IRQREC_S5(sp)
        lw      s4, IRQREC_S4(sp)
        lw      s3, IRQREC_S3(sp)
        lw      s2, IRQREC_S2(sp)
        lw      s1, IRQREC_S1(sp)
        lw      s0, IRQREC_S0(sp)
        lw      t7, IRQREC_T7(sp)
        lw      t6, IRQREC_T6(sp)
        lw      t5, IRQREC_T5(sp)
        lw      t4, IRQREC_T4(sp)
        lw      t3, IRQREC_T3(sp)
        lw      t2, IRQREC_T2(sp)
        lw      t1, IRQREC_T1(sp)
        lw      t0, IRQREC_T0(sp)
        lw      a3, IRQREC_A3(sp)
        lw      a2, IRQREC_A2(sp)
        lw      a1, IRQREC_A1(sp)
        lw      a0, IRQREC_A0(sp)
        lw      v1, IRQREC_V1(sp)
        lw      v0, IRQREC_V0(sp)

        .set noreorder
        .set noat
        lw    k0, IRQREC_EPC(sp)        /* Restore interrupted PC value */
        lw    AT, IRQREC_AT(sp)         /* Restore assembler temp reg   */
        mtc0  k0, CP0_EPC

dismiss:
	lw    k0, IRQREC_STATUS(sp)     /* Restore global status reg    */
        addiu sp, sp, IRQREC_SIZE       /* Restore stack pointer        */
        ori   k0, k0, M_StatusIEn 

	addi  k1, zero, -3         // leave exception mode
	and   k0, k0, k1           // check this

	mtc0  k0, CP0_STATUS
        eret                            /* Return from interrupt        */
	nop
	nop
        .end _excp_0200
	#----------------------------------------------------------------


        .org x_EXCEPTION_BFC0,0
        .ent _excp_BFC0
_excp_BFC0:
        ##
        ##================================================================
        ## exception vector_BFC0 NMI or soft-reset
        ##
        .set noreorder
        .set noat

        la   k0, x_IO_BASE_ADDR
        mfc0 k1, CP0_CAUSE
        sw   k1, 0(k0)        # print CAUSE, flush pipe and stop simulation
        nop
        nop
        nop
        wait 0x1f             # signal exception and abort simulation
        nop
        .end _excp_BFC0
        ##---------------------------------------------------------------


	#================================================================	
	;# print a message from within "the kernel"
	;#   void cmips_kmsg( $k1 )
	;# this function preserves registers other than k0,k1
	#
	.bss
        .align  2
_kmsg_saves:	.space 4*4		# area to save 4 registers
		# _kmsg_saves[0]=a0, [1]=a1, [2]=a2, [3]=a3

	.text
	.align  2
	.set    noreorder
	.set    noat
	.equ	stdout,(x_IO_BASE_ADDR + 1*x_IO_ADDR_RANGE);

	.global cmips_kmsg
	.ent    cmips_kmsg
cmips_kmsg:
	lui   k0, %hi(_kmsg_saves)
	ori   k0, k0, %lo(_kmsg_saves)
	sw    a0, 0*4(k0)
	sw    a1, 1*4(k0)
	sw    a2, 2*4(k0)
	
	lui   a1, %hi(_kmsg_list)
	ori   a1, a1, %lo(_kmsg_list)

	sll   k1, k1, 2		# adjust index onto table
	addu  a1, a1, k1
	lw    a1, 0(a1)		# de-reference pointer
	
	lui   a2, %hi(stdout)
	ori   a2, a2, %lo(stdout)
	
k_for:	lbu   a0, 0(a1)
	addiu a1, a1, 1
	bne   a0, zero, k_for
	sb    a0, 0(a2)		# send it to simulator's stdout
	
	lw    a0, 0*4(k0)
	lw    a1, 1*4(k0)
	jr    ra
	lw    a2, 2*4(k0)

	.end    cmips_kmsg

	.equ kmsg_interr,0
	.equ kmsg_excep,1

	.section .rodata
        .align  2
_kmsg_interr:	.asciiz "\n\t00 - interrupt\n\n"
_kmsg_excep:	.asciiz "\n\t01 - exception\n\n"
_kmsg_prot_viol:	.asciiz "\n\t02 - protection violation\n\n"
_kmsg_seg_fault: 	.asciiz "\n\t03 - segmentation fault\n\n"
_kmsg_sec_mem: 		.asciiz "\n\t04 - in secondary memory\n\n"

	.global _kmsg_list
	.section .rodata
        .align  2
_kmsg_list:
	.word _kmsg_interr,_kmsg_excep, _kmsg_prot_viol, _kmsg_seg_fault
	.word _kmsg_sec_mem

	##
	## need this so the allocation of the PageTable does not break B^(
	##
	.section .data
        .align  2
_end_of_data:
	.word 0

	#----------------------------------------------------------------






        #----------------------------------------------------------------
        # delays processing by approx 4*a0 processor cycles
        .text
        .set    noreorder
        .global cmips_delay, delay_cycle, delay_us, delay_ms
        .ent    cmips_delay
delay_cycle:
cmips_delay:
        beq   a0, zero, _d_cye
        nop
_d_cy:  addiu a0, a0, -1
        nop
        bne   a0, zero, _d_cy
        nop
_d_cye: jr    ra
        nop
        .end    cmips_delay
        #----------------------------------------------------------------

        #================================================================
        # delays processing by a0 times 1 microsecond
        #   loop takes 5 cycles = 100ns @ 50MHz
        #   1.000ns / 100 = 10
        .text
        .set    noreorder
        .ent    delay_us
delay_us:
        beq   a0, zero, _d_use
        nop
        li    v0, 10
        mult  v0, a0
        nop
        mflo  a0
        sra   a0, a0, 1
_d_us:  addiu a0, a0, -1
        nop
        nop
        bne   a0, zero, _d_us
        nop
_d_use: jr    ra
        nop
        .end    delay_us
        #----------------------------------------------------------------

        #================================================================
        # delays processing by a0 times 1 mili second
        #   loop takes 5 cycles = 100ns @ 50MHz
        #   1.000.000ns / 100 = 10.000
        .text
        .set    noreorder
        .ent    delay_ms
delay_ms:
        beq   a0, zero, _d_mse
        nop
        li    v0, 10000
        mul   a0, v0, a0
        nop
_d_ms:  addiu a0, a0, -1
        nop
        nop
        bne   a0, zero, _d_ms
        nop
_d_mse: jr    ra
        nop
        .end    delay_ms
        #----------------------------------------------------------------


        ##
        ##================================================================
        ## put the interrupt and trap vectors here, at start of RAM
	##   see compile/ld.script for memory map
        ##
        ##===============================================================
        ## reserve first 1024 bytes for the exception/interrupt Vectors
        ##
	## .global _EXCP_VEC, _endEXCP_VEC
	## .global exceptionVector
	## .global interruptVector
        ## .section .excp,"aw",@progbits

#_EXCP_VEC:	
#TRAPVEC_ADDR:
#exceptionVector: .skip 0x0080,0
#
#interruptVector: .skip 0x0040,0
#IRQVEC_END:
#_endEXCP_VEC:


        #================================================================
        # read the page table:
        # int PT_read(void *V_addr, int component)
        #   component is in {0=entrylo0, 1-int0, 2=entrylo1, 3=int1}
        .text
        .global PT_read

        .set noreorder
        .ent PT_read
PT_read:
        srl  a0, a0, 9        # (_PT + (V_addr >>13)*16)
        la   v0, PTbase
        add  a0, v0, a0
        andi a1, a1, 0x0003   # make sure component is in range
        sll  a1, a1, 2        # component * 4
        add  a0, a0, a1      # (_PT + (V_addr >>13)*16).component
        jr   ra
        lw   v0, 0(a0)        # return PT[V_addr].component
        .end PT_read
        ##---------------------------------------------------------------


         #================================================================
        # update/modify the page table:
        # void PT_update(void *V_addr, int component, int new_value)
        #   component is in {0=entrylo0, 1-int0, 2=entrylo1, 3=int1}
        .text
        .global PT_update

        .set noreorder
        .ent PT_update
PT_update:
        srl  a0, a0, 9        # (_PT + (V_addr >>13)*16)
        la   v0, PTbase
        add  a0, v0, a0
        andi a1, a1, 0x0003   # make sure component is in range
        sll  a1, a1, 2        # component * 4
        add  a0, a0, a1      # (_PT + (V_addr >>13)*16).component
        jr   ra
        sw   a2, 0(a0)        # write to PT[V_addr].component
        .end PT_update
        ##---------------------------------------------------------------




##===============================================================
#from cmips/include/handlers.s

	#=================================================================
	# handle TLB Modified exception -- store to page with bit dirty=0
	#
	# (a) fix TLB entry, by setting dirty=1 ;
	# (b) check permissions in PT entry and (maybe) kill the process
	#     OR mark PT entry as Used and Modified, then
	#     update TLB entry.
	#
	.global _excp_saves
	.global _excp_0180ret
	.global handle_Mod
	.set noreorder

	.equ TP_UNMAP,   0x0000
	.equ TP_MAPPED,  0x0003  # mapped OR on sec-mem OR locked
	.equ TP_SEC_MEM, 0x0002  # on sec-mem
	.equ TP_LOCKED,  0x0003  # locked
	.equ TP_WR_ABLE, 0x0008  # locked
	.equ TP_USED,	0x0010	# page was referenced
	.equ TP_MODIF,	0x0020	# page was modified (is dirty)
	.equ TLB_DIRTY,	0x0004	# page was modified (is dirty)
	
	.ent handle_Mod
handle_Mod:			# EntryHi points to offending TLB entry
	tlbp			# what is the offender's index?
	lui  k1, %hi(_excp_saves)
        ori  k1, k1, %lo(_excp_saves)
	sw   a0,  9*4(k1)	# save registers
	sw   a1, 10*4(k1)
	sw   a2, 11*4(k1)

	mfc0 a0, c0_badvaddr
	andi a0, a0, 0x1000	# check if even or odd page
	beq  a0, zero, M_even
	mfc0 a0, c0_context

M_odd:	addi a2, a0, 12	# address for odd entry (intLo1)
	mfc0 k0, c0_entrylo1
	ori  k0, k0, TLB_DIRTY # mark TLB entry as dirty/writable
	j    M_test
	mtc0 k0, c0_entrylo1
	
M_even: addi a2, a0, 4	# address for even entry (intLo0)
	mfc0 k0, c0_entrylo0
	ori  k0, k0, TLB_DIRTY # mark TLB entry as dirty/writable
	mtc0 k0, c0_entrylo0

M_test:	lw   a1, 0(a2)	# read PT[badVAddr].intLo{0,1}
	mfc0 k0, c0_badvaddr	# get faulting address
	andi a0, a1, TP_MAPPED	# check if page is mapped
	nop
	beq  a0, zero, M_seg_fault	# no, abort simulation
	nop

	andi a0, a1, TP_WR_ABLE	# check if page is writable
	nop
	beq  a0, zero, M_prot_viol	# no, abort simulation
	nop

	andi a0, a1, TP_SEC_MEM	# check if page is in secondary memory
	nop
	bne  a0, zero, M_sec_mem	# yes, abort simulation
	nop

	mfc0 a0, c0_epc	# check if fault is on an instruction
	nop
	beq  a0, k0, M_prot_viol	# k0 is badVAddr, if so, abort
	nop

	ori  a1, a1, (TP_USED | TP_MODIF) # mark PT entry as modified, used
	sw   a1, 0(a2)

	tlbwi			# write entry with dirty bit=1 back to TLB
	
	lw   a0,  9*4(k1)	# restore saved registers and return
	lw   a1, 10*4(k1)
	lw   a2, 11*4(k1)
	j    _excp_0180ret
	nop
	
M_seg_fault:	# print message and abort simulation
	la   k1, x_IO_BASE_ADDR
	sw   k0, 0(k1)
	jal  cmips_kmsg
	la   k1, 3		# segmentation fault
	nop
	nop
	nop
	wait 0x31
	
M_prot_viol:	# print message and abort simulation
	la   k1, x_IO_BASE_ADDR
	sw   k0, 0(k1)
	jal  cmips_kmsg
	la   k1, 2		# protection violation
	nop
	nop
	nop
	wait 0x32

M_sec_mem:	# print message and abort simulation
	la   k1, x_IO_BASE_ADDR
	sw   k0, 0(k1)
	jal  cmips_kmsg
	la   k1, 4		# secondary memory
	nop
	nop
	nop
	wait 0x33
	
	.end handle_Mod
	#----------------------------------------------------------------


	#================================================================
	# handle TLB Load exception: double-fault caused by a TLB miss
	#   to the Page Table -- mapping which points to PT is not on TLB
	#
	# (a) fix the fault by (re)loading the mapping into TLB[4];
	# (b) check permissions in PT entry and (maybe) kill the process.
	#
	.global handle_TLBL
	.global _PT
        .set MIDDLE_RAM, (x_DATA_BASE_ADDR + (x_DATA_MEM_SZ/2))

	.ent handle_TLBL
handle_TLBL:			# EntryHi points to offending TLB entry
	tlbp			# probe it to find the offender's index
	lui  k1, %hi(_excp_saves)
        ori  k1, k1, %lo(_excp_saves)
	sw   a0,  9*4(k1)
	sw   a1, 10*4(k1)
	sw   a2, 11*4(k1)

	mfc0 a0, c0_badvaddr

	# check is fault is to address below the PT
	la   a1, (_PT + (x_INST_BASE_ADDR >>13)*16)

	slt  a2, a0, a1	# a2 <- (badVAddr <= PageTable_bottom)
	bne  a2, zero, L_chks	#   fault is not to PageTable
	nop

	# check is fault is to address above the PT
	# la   a1, ( (_PT+4*4096) + (x_INST_BASE_ADDR >>13)*16)

	# slt  a2, a1, a0	# a2 <- (badVAddr > PageTable_top)
	# bne  a2, zero, L_chks	#   fault is not to PageTable
	# nop
	
	# this is same code as in start.s
        # get physical page number for two pages at the bottom of PageTable
        la    a0, ( MIDDLE_RAM >>13 )<<13
        mtc0  a0, c0_entryhi           # tag for bottom double-page

        la    a0, ( (MIDDLE_RAM + 0*4096) >>12 )<<6
        ori   a1, a0, 0b00000000000000000000000000000111 # ccc=0, d,v,g1
        mtc0  a1, c0_entrylo0          # bottom page (even)

        la    a0, ( (MIDDLE_RAM + 1*4096) >>12 )<<6
        ori   a1, a0, 0b00000000000000000000000000000111 # ccc=0, d,v,g1
        mtc0  a1, c0_entrylo1          # bottom page + 1 (odd)

        # and write it to TLB[4]
        li    k0, 4
        mtc0  k0, c0_index
        tlbwi
	j     L_ret		# all work done, return
	nop

L_chks: andi a0, a0, 0x1000	# check if even or odd page
	nop
	beq  a0, zero, L_even
	mfc0 a0, c0_context

L_odd:	j    L_test
	addi a2, a0, 12	# address for odd intLo1 entry
	
L_even: addi a2, a0, 4	# address for even intLo0 entry

L_test:	lw   a1, 0(a2)	# get intLo{0,1}
	mfc0 k0, c0_badvaddr	# get faulting address for printing
	andi a0, a1, TP_MAPPED # check if page is mapped
	nop
	beq  a0, zero, M_seg_fault	# no, abort simulation
	nop

	andi a0, a1, TP_SEC_MEM	# check if page is in secondary memory
	nop
	bne  a0, zero, M_sec_mem	# yes, abort simulation
	nop

	ori  a1, a1, TP_USED	# mark PT entry as used
	# sw   a1, 0(a2)

	;# if this were handler_TLBS, now is the time to also mark the
	;#    PT entry as Modified
	;# mark PT entry as used, writable and modified
	ori  a1, a1, (TP_USED | TP_MODIF | TP_WR_ABLE)
	sw   a1, 0(a2)
	
L_ret:	lw   a0,  9*4(k1)	# nothing else to do, return
	lw   a1, 10*4(k1)
	lw   a2, 11*4(k1)
	j    _excp_0180ret
	nop

	.end handle_TLBL
	#----------------------------------------------------------------


	#================================================================
	# purge an entry from the TLB
	# int TLB_purge(void *V_addr)
	#   returns 0 if V_addr purged, 1 if V_addr not in TLB (probe failure)
	#
	.global TLB_purge
	.text
	.set noreorder
	.ent TLB_purge
TLB_purge:
	srl  a0, a0, 13	# clear out in-page address bits
	sll  a0, a0, 13	# 
	mtc0 a0, c0_entryhi
	nop
	tlbp			# probe the TLB
	nop
	mfc0 a0, c0_index	# check for hit
	srl  a0, a0, 31	# keeo only MSbit
	nop
	bne  a0, zero, pu_miss # address not in TLB
	move v0, a0		# V_addr not in TLB

	tlbr			# read the entry
	li   a0, -8192		# -8192 = 0xffff.e000
	mtc0 a0, c0_entryhi	# and write an un-mapped address to tag

	addi v0, zero, -3	# -3 = 0xffff.fffd to clear valid bit
	mfc0 a0, c0_entrylo0	# invalidate the mappings
	and  a0, v0, a0
	mtc0 a0, c0_entrylo0

	mfc0 a0, c0_entrylo1
	and  a0, v0, a0
	mtc0 a0, c0_entrylo1
	move v0, zero		# V_addr was purged from TLB

	tlbwi			# write invalid mappings to TLB
	ehb
	
pu_miss: jr  ra
	nop
	.end TLB_purge
	##---------------------------------------------------------------


	#================================================================	
	# print message to simulator's stdout end stop simulation
	#
	# k0 holds exception code
	# exception_report(code, cause, epc, badVAddr)
	.text
	.global excp_report, exception_report
	.ent excp_report
excp_report:
	srl  a0, k0, 3
	mfc0 a1, c0_cause
	mfc0 a2, c0_epc
	mfc0 a3, c0_badvaddr
	# jal cmips_kmsg
        nop
_do_halt: j _do_halt
	nop
	.end excp_report



	
	#----------------------------------------------------------------
	# interrupt handler for external counter attached to IP5=HW3
	# for extCounter address see vhdl/packageMemory.vhd

	.bss
	.align  2
	.set noreorder
	.global _counter_val             # accumulate number of interrupts
	.comm   _counter_val 4
	.comm   _counter_saves 8*4       # area to save up to 8 registers
	# _counter_saves[0]=a0, [1]=a1, [2]=a2, ...
	
	.set HW_counter_value,0xc00000c8 # Count 200 clock pulses & interr

	.text
	.set    noreorder
	.global extCounter
	.ent    extCounter

extCounter:
	lui   k0, %hi(HW_counter_addr)
	ori   k0, k0, %lo(HW_counter_addr)
	sw    zero, 0(k0) 	# Reset counter, remove interrupt request

	#----------------------------------
	# save additional registers
	# lui k1, %hi(_counter_saves)
	# ori k1, k1, %lo(_counter_saves)
	# sw  a0, 0*4(k1)
	# sw  a1, 1*4(k1)
	#----------------------------------
	
	lui   k1, %hi(HW_counter_value)
	ori   k1, k1, %lo(HW_counter_value)
	sw    k1, 0(k0)	      # Reload counter so it starts again

	lui   k0, %hi(_counter_val)  # Increment interrupt event counter
	ori   k0, k0, %lo(_counter_val)
	lw    k1,0(k0)
	nop
	addiu k1,k1,1
	sw    k1,0(k0)

	#----------------------------------
	# and then restore those same registers
	# lui k1, %hi(_counter_saves)
	# ori k1, k1, %lo(_counter_saves)
	# lw  a0, 0*4(k1)
	# lw  a1, 1*4(k1)
	#----------------------------------
	
	eret			    # Return from interrupt
	.end extCounter
	#----------------------------------------------------------------

	
	#----------------------------------------------------------------
	# interrupt handler for UART attached to IP6=HW4

	.bss 
        .align  2
	.set noreorder
	.global Ud

        .equ RXHD,0
        .equ RXTL,4
        .equ RX_Q,8
        .equ TXHD,24
        .equ TXTL,28
        .equ TXQ,32
        .equ NRX,48
        .equ NTX,52
	
Ud:
rx_hd:  .space 4        # reception queue head index
rx_tl:  .space 4        # tail index
rx_q:   .space 16       # reception queue
tx_hd:  .space 4        # transmission queue head index
tx_tl:  .space 4        # tail index
tx_q:   .space 16       # transmission queue
nrx:    .space 4        # characters in RX_queue
ntx:    .space 4        # spaces left in TX_queue

_uart_buff: .space 16*4 # up to 16 registers to be saved here
        # _uart_buff[0]=UARTstatus, [1]=UARTcontrol, [2]=v0, [3]=v1,
        #           [4]=ra, [5]=a0, [6]=a1, [7]=a2, [8]=a3

        .set U_rx_irq,0x08
        .set U_tx_irq,0x10

        .equ UCTRL,0    # UART registers
        .equ USTAT,4
        .equ UINTER,8
        .equ UDATA,12

	.text
	.set    noreorder
	.global UARTinterr
	.ent    UARTinterr

UARTinterr:

        #----------------------------------------------------------------
        ;# While you are developing the complete handler, uncomment the
        ;#   line below
        ;#
        ;# .include "../tests/handlerUART.s"
        ;#
        ;# Your new handler should be self-contained and do the
        ;#   return-from-exception.  To do that, copy the lines below up
        ;#   to, but excluding, ".end UARTinterr", to yours handlerUART.s.
        #----------------------------------------------------------------

        lui   k0, %hi(_uart_buff)  # get buffer's address
        ori   k0, k0, %lo(_uart_buff)

        sw    a0, 5*4(k0)         # save registers a0,a1, others?
        sw    a1, 6*4(k0)
        sw    a2, 7*4(k0)

        lui   a0, %hi(HW_uart_addr)# get device's address
        ori   a0, a0, %lo(HW_uart_addr)

        lw    k1, USTAT(a0)       # Read status
        sw    k1, 0*4(k0)         #  and save UART status to memory

        li    a1, U_rx_irq         # remove interrupt request
        sw    a1, UINTER(a0)

        and   a1, k1, a1         # Is this reception?
        beq   a1, zero, UARTret   #   no, ignore it and return
        nop

        # handle reception
        lw    a1, UDATA(a0)       # Read data from device

        lui   a2, %hi(Ud)          # get address for data & flag
        ori   a2, a2, %lo(Ud)

        sw    a1, 0*4(a2)         #   and return from interrupt
        addiu a1, zero, 1
        sw    a1, 1*4(a2)         # set flag to signal new arrival 

UARTret:
        lw    a2, 7*4(k0)
        lw    a1, 6*4(k0)         # restore registers a0,a1, others?
        lw    a0, 5*4(k0)

        eret                        # Return from interrupt
        .end UARTinterr
	#----------------------------------------------------------------

	
	#----------------------------------------------------------------
	# handler for COUNT-COMPARE registers -- IP7=HW5
	.text
	.set    noreorder
        .equ    num_cycles, 64
	.global countCompare
	.ent    countCompare
countCompare:	
        mfc0  k1,c0_count       # read COUNT
        addiu k1,k1,num_cycles # set next interrupt in so many ticks
        mtc0  k1,c0_compare     # write to COMPARE to clear IRQ

        eret                     # Return from interrupt
	.end countCompare
	#----------------------------------------------------------------

	






##---------------------------------------------------------------

       ##===============================================================
        ## Page Table
        ##
        ## See EntryLo, pg 63
        ##
        ## intLo0 and intLo1 are:
        ## nil_31..6 Modified_5 Used_4  Writable_3  eXecutable_2 Status_1,0
        ## Status: 00=unmapped, 01=mapped, 10=in_secondary_storage, 11=locked
        ##
        .section .PT,"aw",@progbits
        .align 4
        .global _PT

        ## ( ( (x_INST_BASE_ADDR + n*4096) >>12 )<<6 ) || 0b000011  d,v,g
        ##
        ## ROM mappings
        ##
        ## mapped pages:   intLo{01} = U=M=W=0, X=1, S=01 = 5
        ## UNmapped pages: intLo{01} = U=M=W=0, X=1, S=00 = 4
        ##
_PT:    .org (_PT + (x_INST_BASE_ADDR >>13)*16)

        # PT[0], ROM
PTbase: .word  ( (x_INST_BASE_ADDR +  0*4096) >>6) | 0b000011  
        .word 0x00000005
        .word  ( (x_INST_BASE_ADDR +  1*4096) >>6) | 0b000011  
        .word 0x00000005

        # PT[1]
        .word  ( (x_INST_BASE_ADDR +  2*4096) >>6) | 0b000011  
        .word 0x00000005
        .word  ( (x_INST_BASE_ADDR +  3*4096) >>6) | 0b000011  
        .word 0x00000005

        # PT[2] -- not mapped for simulation
        .word  ( (x_INST_BASE_ADDR +  4*4096) >>6) | 0b000001  
        .word 0x00000004
        .word  ( (x_INST_BASE_ADDR +  5*4096) >>6) | 0b000001  
        .word 0x00000004

        # PT[3] -- not mapped for simulation
        .word  ( (x_INST_BASE_ADDR +  6*4096) >>6) | 0b000001  
        .word 0x00000004
        .word  ( (x_INST_BASE_ADDR +  7*4096) >>6) | 0b000001  
        .word 0x00000004

        # PT[4] -- not mapped for simulation
        .word  ( (x_INST_BASE_ADDR +  8*4096) >>6) | 0b000001
        .word 0x00000004
        .word  ( (x_INST_BASE_ADDR +  9*4096) >>6) | 0b000001
        .word 0x00000004

        # PT[5] -- not mapped for simulation
        .word  ( (x_INST_BASE_ADDR + 10*4096) >>6) | 0b000001
        .word 0x00000004
        .word  ( (x_INST_BASE_ADDR + 11*4096) >>6) | 0b000001
        .word 0x00000004

        # PT[6] -- not mapped for simulation
        .word  ( (x_INST_BASE_ADDR + 12*4096) >>6) | 0b000001
        .word 0x00000004
        .word  ( (x_INST_BASE_ADDR + 13*4096) >>6) | 0b000001
        .word 0x00000004

        # PT[7] -- not mapped for simulation
        .word  ( (x_INST_BASE_ADDR + 14*4096) >>6) | 0b000001
        .word 0x00000004
        .word  ( (x_INST_BASE_ADDR + 15*4096) >>6) | 0b000001
        .word 0x00000004

        ## remaining ROM entries are invalid and unmapped (0 filled by AS)



        ##
        ## RAM mappings
        ##
        ## mapped pages:       intLo{01} = U=M=0, W=1, X=0, S=01 = 9
        ## UNmapped pages:     intLo{01} = U=M=0, W=1, X=0, S=00 = 8
        ## mapped pages, disk: intLo{01} = U=M=0, W=1, X=0, S=10 = a
        ##
        .org (_PT + (x_DATA_BASE_ADDR >>13)*16)

        ## ( ( (x_DATA_BASE_ADDR + n*4096) >>12 )<<6 ) || 0b000111  d,v,g

        # PT[ram+0], RAM
        .word  ( (x_DATA_BASE_ADDR +  0*4096) >>6) | 0b000111  
        .word 0x00000009
        .word  ( (x_DATA_BASE_ADDR +  1*4096) >>6) | 0b000111  
        .word 0x00000009

        # PT[ram+1]
        .word  ( (x_DATA_BASE_ADDR +  2*4096) >>6) | 0b000111  
        .word 0x00000009
        .word  ( (x_DATA_BASE_ADDR +  3*4096) >>6) | 0b000111  
        .word 0x00000009

        # PT[ram+2]
        .word  ( (x_DATA_BASE_ADDR +  4*4096) >>6) | 0b000111  
        .word 0x00000009
        .word  ( (x_DATA_BASE_ADDR +  5*4096) >>6) | 0b000111  
        .word 0x00000009

        # PT[ram+3]
        .word  ( (x_DATA_BASE_ADDR +  6*4096) >>6) | 0b000111  
        .word 0x00000009
        .word  ( (x_DATA_BASE_ADDR +  7*4096) >>6) | 0b000111  
        .word 0x00000009

        # PT[ram+4]
        .word  ( (x_DATA_BASE_ADDR +  8*4096) >>6) | 0b000111  
        .word 0x00000009
        .word  ( (x_DATA_BASE_ADDR +  9*4096) >>6) | 0b000111  
        .word 0x00000009

        # PT[ram+5]
        .word  ( (x_DATA_BASE_ADDR + 10*4096) >>6) | 0b000111  
        .word 0x00000009
        .word  ( (x_DATA_BASE_ADDR + 11*4096) >>6) | 0b000111  
        .word 0x00000009

        # PT[ram+6]
        .word  ( (x_DATA_BASE_ADDR + 12*4096) >>6) | 0b000111   # 000001
        .word 0x00000009   # a
        .word  ( (x_DATA_BASE_ADDR + 13*4096) >>6) | 0b000111   # 000001
        .word 0x00000009   # a

        # PT[ram+7]
        .word  ( (x_DATA_BASE_ADDR + 14*4096) >>6) | 0b000111  
        .word 0x00000009
        .word  ( (x_DATA_BASE_ADDR + 15*4096) >>6) | 0b000111  
        .word 0x00000009

        #PT[ram+8]
        .word  ( (x_DATA_BASE_ADDR +  16*4096) >>6) | 0b000111
        .word 0x00000009
        .word  ( (x_DATA_BASE_ADDR +  17*4096) >>6) | 0b000111
        .word 0x00000009

        #PT[ram+9]
        .word  ( (x_DATA_BASE_ADDR +  18*4096) >>6) | 0b000111
        .word 0x00000009
        .word  ( (x_DATA_BASE_ADDR +  19*4096) >>6) | 0b000111
        .word 0x00000009

        #PT[ram+10]
        .word  ( (x_DATA_BASE_ADDR +  20*4096) >>6) | 0b000111
        .word 0x00000009
        .word  ( (x_DATA_BASE_ADDR +  21*4096) >>6) | 0b000111
        .word 0x00000009

        #PT[ram+11]
        .word  ( (x_DATA_BASE_ADDR +  22*4096) >>6) | 0b000111
        .word 0x00000009
        .word  ( (x_DATA_BASE_ADDR +  23*4096) >>6) | 0b000111
        .word 0x00000009

        #PT[ram+12]
        .word  ( (x_DATA_BASE_ADDR +  24*4096) >>6) | 0b000111
        .word 0x00000009
        .word  ( (x_DATA_BASE_ADDR +  25*4096) >>6) | 0b000111
        .word 0x00000009

        #PT[ram+13]
        .word  ( (x_DATA_BASE_ADDR +  26*4096) >>6) | 0b000111
        .word 0x00000009
        .word  ( (x_DATA_BASE_ADDR +  27*4096) >>6) | 0b000111
        .word 0x00000009

        #PT[ram+14]
        .word  ( (x_DATA_BASE_ADDR +  28*4096) >>6) | 0b000111
        .word 0x00000009
        .word  ( (x_DATA_BASE_ADDR +  29*4096) >>6) | 0b000111
        .word 0x00000009

        #PT[ram+15]
        .word  ( (x_DATA_BASE_ADDR +  30*4096) >>6) | 0b000111
        .word 0x00000009
        .word  ( (x_DATA_BASE_ADDR +  31*4096) >>6) | 0b000111
        .word 0x00000009

        #PT[ram+16]
        .word  ( (x_DATA_BASE_ADDR +  32*4096) >>6) | 0b000111
        .word 0x00000009
        .word  ( (x_DATA_BASE_ADDR +  33*4096) >>6) | 0b000111
        .word 0x00000009

        #PT[ram+17]
        .word  ( (x_DATA_BASE_ADDR +  34*4096) >>6) | 0b000111
        .word 0x00000009
        .word  ( (x_DATA_BASE_ADDR +  35*4096) >>6) | 0b000111
        .word 0x00000009

        #PT[ram+18]
        .word  ( (x_DATA_BASE_ADDR +  36*4096) >>6) | 0b000111
        .word 0x00000009
        .word  ( (x_DATA_BASE_ADDR +  37*4096) >>6) | 0b000111
        .word 0x00000009

        #PT[ram+19]
        .word  ( (x_DATA_BASE_ADDR +  38*4096) >>6) | 0b000111
        .word 0x00000009
        .word  ( (x_DATA_BASE_ADDR +  39*4096) >>6) | 0b000111
        .word 0x00000009

        #PT[ram+20]
        .word  ( (x_DATA_BASE_ADDR +  40*4096) >>6) | 0b000111
        .word 0x00000009
        .word  ( (x_DATA_BASE_ADDR +  41*4096) >>6) | 0b000111
        .word 0x00000009

        #PT[ram+21]
        .word  ( (x_DATA_BASE_ADDR +  42*4096) >>6) | 0b000111
        .word 0x00000009
        .word  ( (x_DATA_BASE_ADDR +  43*4096) >>6) | 0b000111
        .word 0x00000009

        #PT[ram+22]
        .word  ( (x_DATA_BASE_ADDR +  44*4096) >>6) | 0b000111
        .word 0x00000009
        .word  ( (x_DATA_BASE_ADDR +  45*4096) >>6) | 0b000111
        .word 0x00000009

        #PT[ram+23]
        .word  ( (x_DATA_BASE_ADDR +  46*4096) >>6) | 0b000111
        .word 0x00000009
        .word  ( (x_DATA_BASE_ADDR +  47*4096) >>6) | 0b000111
        .word 0x00000009

        #PT[ram+24]
        .word  ( (x_DATA_BASE_ADDR +  48*4096) >>6) | 0b000111
        .word 0x00000009
        .word  ( (x_DATA_BASE_ADDR +  49*4096) >>6) | 0b000111
        .word 0x00000009

        #PT[ram+25]
        .word  ( (x_DATA_BASE_ADDR +  50*4096) >>6) | 0b000111
        .word 0x00000009
        .word  ( (x_DATA_BASE_ADDR +  51*4096) >>6) | 0b000111
        .word 0x00000009

        #PT[ram+26]
        .word  ( (x_DATA_BASE_ADDR +  52*4096) >>6) | 0b000111
        .word 0x00000009
        .word  ( (x_DATA_BASE_ADDR +  53*4096) >>6) | 0b000111
        .word 0x00000009

        #PT[ram+27]
        .word  ( (x_DATA_BASE_ADDR +  54*4096) >>6) | 0b000111
        .word 0x00000009
        .word  ( (x_DATA_BASE_ADDR +  55*4096) >>6) | 0b000111
        .word 0x00000009

        #PT[ram+28]
        .word  ( (x_DATA_BASE_ADDR +  56*4096) >>6) | 0b000111
        .word 0x00000009
        .word  ( (x_DATA_BASE_ADDR +  57*4096) >>6) | 0b000111
        .word 0x00000009

        #PT[ram+29]
        .word  ( (x_DATA_BASE_ADDR +  58*4096) >>6) | 0b000111
        .word 0x00000009
        .word  ( (x_DATA_BASE_ADDR +  59*4096) >>6) | 0b000111
        .word 0x00000009

        #PT[ram+30]
        .word  ( (x_DATA_BASE_ADDR +  60*4096) >>6) | 0b000111
        .word 0x00000009
        .word  ( (x_DATA_BASE_ADDR +  61*4096) >>6) | 0b000111
        .word 0x00000009

        #PT[ram+31]
        .word  ( (x_DATA_BASE_ADDR +  62*4096) >>6) | 0b000111
        .word 0x00000009
        .word  ( (x_DATA_BASE_ADDR +  63*4096) >>6) | 0b000111
        .word 0x00000009

        ## remaining RAM entries are invalid and unmapped (0 filled by AS)
        # .space (5*4096 - 8*16), 0

_endPT:
