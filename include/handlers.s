	# interrupt handlers
	.include "cMIPS.s"
	.text
	.set noreorder
        .align 2

	.set M_StatusIEn,0x0000ff09     # STATUS.intEn=1, user mode
	
	#----------------------------------------------------------------
	# interrupt handler for external counter attached to IP5=HW3
	# for extCounter address see vhdl/packageMemory.vhd

	.bss
	.align  2
	.set noreorder
	.global _counter_val             # accumulate number of interrupts
	.comm   _counter_val 4
	.comm   _counter_saves 8*4       # area to save up to 8 registers
	# _counter_saves[0]=$a0, [1]=$a1, [2]=$a2, ...
	
	.set HW_counter_value,0xc00000c8 # Count 200 clock pulses & interr

	.text
	.set    noreorder
	.global extCounter
	.ent    extCounter

extCounter:
	lui   $k0, %hi(HW_counter_addr)
	ori   $k0, $k0, %lo(HW_counter_addr)
	sw    $zero, 0($k0) 	# Reset counter, remove interrupt request

	#----------------------------------
	# save additional registers
	# lui $k1, %hi(_counter_saves)
	# ori $k1, $k1, %lo(_counter_saves)
	# sw  $a0, 0*4($k1)
	# sw  $a1, 1*4($k1)
	#----------------------------------
	
	lui   $k1, %hi(HW_counter_value)
	ori   $k1, $k1, %lo(HW_counter_value)
	sw    $k1, 0($k0)	      # Reload counter so it starts again

	lui   $k0, %hi(_counter_val)  # Increment interrupt event counter
	ori   $k0, $k0, %lo(_counter_val)
	lw    $k1,0($k0)
	nop
	addiu $k1,$k1,1
	sw    $k1,0($k0)

	#----------------------------------
	# and then restore those same registers
	# lui $k1, %hi(_counter_saves)
	# ori $k1, $k1, %lo(_counter_saves)
	# lw  $a0, 0*4($k1)
	# lw  $a1, 1*4($k1)
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
        # _uart_buff[0]=UARTstatus, [1]=UARTcontrol, [2]=$v0, [3]=$v1,
        #           [4]=$ra, [5]=$a0, [6]=$a1, [7]=$a2, [8]=$a3

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
        # While you are developing the complete handler, uncomment the
        #   line below
        #
        # .include "../tests/handlerUART.s"
        #
        # Your new handler should be self-contained and do the
        #   return-from-exception.  To do that, copy the lines below up
        #   to, but excluding, ".end UARTinterr", to yours handlerUART.s.
        #----------------------------------------------------------------

        lui   $k0, %hi(_uart_buff)  # get buffer's address
        ori   $k0, $k0, %lo(_uart_buff)

        sw    $a0, 5*4($k0)         # save registers $a0,$a1, others?
        sw    $a1, 6*4($k0)
        sw    $a2, 7*4($k0)

        lui   $a0, %hi(HW_uart_addr)# get device's address
        ori   $a0, $a0, %lo(HW_uart_addr)

        lw    $k1, USTAT($a0)       # Read status
        sw    $k1, 0*4($k0)         #  and save UART status to memory

        li    $a1, U_rx_irq         # remove interrupt request
        sw    $a1, UINTER($a0)

        and   $a1, $k1, $a1         # Is this reception?
        beq   $a1, $zero, UARTret   #   no, ignore it and return
        nop

        # handle reception
        lw    $a1, UDATA($a0)       # Read data from device

        lui   $a2, %hi(Ud)          # get address for data & flag
        ori   $a2, $a2, %lo(Ud)

        sw    $a1, 0*4($a2)         #   and return from interrupt
        addiu $a1, $zero, 1
        sw    $a1, 1*4($a2)         # set flag to signal new arrival 

UARTret:
        lw    $a2, 7*4($k0)
        lw    $a1, 6*4($k0)         # restore registers $a0,$a1, others?
        lw    $a0, 5*4($k0)

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
        mfc0  $k1,c0_count       # read COUNT
        addiu $k1,$k1,num_cycles # set next interrupt in so many ticks
        mtc0  $k1,c0_compare     # write to COMPARE to clear IRQ

        eret                     # Return from interrupt
	.end countCompare
	#----------------------------------------------------------------

	
        #================================================================
        # startCount enables the COUNT register, returns new CAUSE
        #   CAUSE.dc <= 0 to enable counting
        #----------------------------------------------------------------
        .text
        .set    noreorder
        .global startCount
        .ent    startCount
startCount:
        mfc0 $v0, c0_cause
        lui  $v1, 0xf7ff
        ori  $v1, $v1, 0xffff
        and  $v0, $v0, $v1
        mtc0 $v0, c0_cause
        ehb
        jr   $ra
        nop
        .end    startCount
        #----------------------------------------------------------------


        #================================================================
        # stopCount disables the COUNT register, returns new CAUSE
        #   CAUSE.dc <= 1 to disable counting
        #----------------------------------------------------------------
        .text
        .set    noreorder
        .global stopCount
        .ent    stopCount
stopCount:
        mfc0 $v0, c0_cause
        lui  $v1, 0x0800
        or   $v0, $v0, $v1
        jr   $ra
        mtc0 $v0, c0_cause
        .end    stopCount
        #----------------------------------------------------------------


        #================================================================
        # readCount returns the value of the COUNT register
        #----------------------------------------------------------------
        .text
        .set    noreorder
        .global readCount
        .ent    readCount
readCount:
        mfc0 $v0, c0_count
        jr   $ra
        nop
        .end    readCount
        #----------------------------------------------------------------

	
	#----------------------------------------------------------------
	# functions to enable and disable interrupts, both return STATUS
	.text
	.set    noreorder
	.global enableInterr,disableInterr
	.ent    enableInterr
enableInterr:
	mfc0  $v0, c0_status	    # Read STATUS register
	ori   $v0, $v0, 1           #   and enable interrupts
	mtc0  $v0, c0_status
	ehb
	jr    $ra                   # return updated STATUS
	nop
	.end enableInterr

	.ent disableInterr
disableInterr:
	mfc0  $v0, c0_status	    # Read STATUS register
	addiu $v1, $zero, -2        #   and disable interrupts
	and   $v0, $v0, $v1         # -2 = 0xffff.fffe
	mtc0  $v0, c0_status
	ehb
	jr    $ra                   # return updated STATUS
	nop
	.end disableInterr
	#----------------------------------------------------------------


	#----------------------------------------------------------------	
	# delays processing by approx 4*$a0 processor cycles
	.text
	.set    noreorder
	.global cmips_delay, delay_cycle, delay_us, delay_ms
	.ent    cmips_delay
delay_cycle:
cmips_delay:
        beq   $a0, $zero, _d_cye
        nop
_d_cy:  addiu $a0, $a0, -1
        nop
        bne   $a0, $zero, _d_cy
        nop
_d_cye: jr    $ra
        nop
        .end    cmips_delay
	#----------------------------------------------------------------

        #================================================================
        # delays processing by $a0 times 1 microsecond
        #   loop takes 5 cycles = 100ns @ 50MHz
        #   1.000ns / 100 = 10
        .text
        .set    noreorder
        .ent    delay_us
delay_us:
        beq   $a0, $zero, _d_use
        nop
        li    $v0, 10
        mult  $v0, $a0
        nop
        mflo  $a0
        sra   $a0, $a0, 1
_d_us:  addiu $a0, $a0, -1
        nop
        nop
        bne   $a0, $zero, _d_us
        nop
_d_use: jr    $ra
        nop
        .end    delay_us
        #----------------------------------------------------------------


        #================================================================
        # delays processing by $a0 times 1 mili second
        #   loop takes 5 cycles = 100ns @ 50MHz
        #   1.000.000ns / 100 = 10.000
        .text
        .set    noreorder
        .ent    delay_ms
delay_ms:
        beq   $a0, $zero, _d_mse
        nop
        li    $v0, 10000
        mul   $a0, $v0, $a0
        nop
_d_ms:  addiu $a0, $a0, -1
        nop
        nop
        bne   $a0, $zero, _d_ms
        nop
_d_mse: jr    $ra
        nop
        .end    delay_ms
        #----------------------------------------------------------------



#=================================================================
	## TLB handlers
	## page table entry is { EntryLo0, int0, EntryLo1, int1 }
	## int{0,1} is
	## { fill_31..6, Modified_5, Used_4, Writable_3, eXecutable_2,
	##    Status_10 },
	## Status: 00=unmapped, 01=mapped, 10=secondary_storage, 11=locked
	#=================================================================
	

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
	lui  $k1, %hi(_excp_saves)
        ori  $k1, $k1, %lo(_excp_saves)
	sw   $a0,  9*4($k1)	# save registers
	sw   $a1, 10*4($k1)
	sw   $a2, 11*4($k1)

	mfc0 $a0, c0_badvaddr
	andi $a0, $a0, 0x1000	# check if even or odd page
	beq  $a0, $zero, M_even
	mfc0 $a0, c0_context

M_odd:	addi $a2, $a0, 12	# address for odd entry (intLo1)
	mfc0 $k0, c0_entrylo1
	ori  $k0, $k0, TLB_DIRTY # mark TLB entry as dirty/writable
	j    M_test
	mtc0 $k0, c0_entrylo1
	
M_even: addi $a2, $a0, 4	# address for even entry (intLo0)
	mfc0 $k0, c0_entrylo0
	ori  $k0, $k0, TLB_DIRTY # mark TLB entry as dirty/writable
	mtc0 $k0, c0_entrylo0

M_test:	lw   $a1, 0($a2)	# read PT[badVAddr].intLo{0,1}
	mfc0 $k0, c0_badvaddr	# get faulting address
	andi $a0, $a1, TP_MAPPED	# check if page is mapped
	nop
	beq  $a0, $zero, M_seg_fault	# no, abort simulation
	nop

	andi $a0, $a1, TP_WR_ABLE	# check if page is writable
	nop
	beq  $a0, $zero, M_prot_viol	# no, abort simulation
	nop

	andi $a0, $a1, TP_SEC_MEM	# check if page is in secondary memory
	nop
	bne  $a0, $zero, M_sec_mem	# yes, abort simulation
	nop

	mfc0 $a0, c0_epc	# check if fault is on an instruction
	nop
	beq  $a0, $k0, M_prot_viol	# k0 is badVAddr, if so, abort
	nop

	ori  $a1, $a1, (TP_USED | TP_MODIF) # mark PT entry as modified, used
	sw   $a1, 0($a2)

	tlbwi			# write entry with dirty bit=1 back to TLB
	
	lw   $a0,  9*4($k1)	# restore saved registers and return
	lw   $a1, 10*4($k1)
	lw   $a2, 11*4($k1)
	j    _excp_0180ret
	nop
	
M_seg_fault:	# print message and abort simulation
	la   $k1, x_IO_BASE_ADDR
	sw   $k0, 0($k1)
	jal  cmips_kmsg
	la   $k1, 3		# segmentation fault
	nop
	nop
	nop
	wait 0x31
	
M_prot_viol:	# print message and abort simulation
	la   $k1, x_IO_BASE_ADDR
	sw   $k0, 0($k1)
	jal  cmips_kmsg
	la   $k1, 2		# protection violation
	nop
	nop
	nop
	wait 0x32

M_sec_mem:	# print message and abort simulation
	la   $k1, x_IO_BASE_ADDR
	sw   $k0, 0($k1)
	jal  cmips_kmsg
	la   $k1, 4		# secondary memory
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
	lui  $k1, %hi(_excp_saves)
        ori  $k1, $k1, %lo(_excp_saves)
	sw   $a0,  9*4($k1)
	sw   $a1, 10*4($k1)
	sw   $a2, 11*4($k1)

	mfc0 $a0, c0_badvaddr

	# check is fault is to address below the PT
	la   $a1, (_PT + (x_INST_BASE_ADDR >>13)*16)

	slt  $a2, $a0, $a1	# a2 <- (badVAddr <= PageTable_bottom)
	bne  $a2, $zero, L_chks	#   fault is not to PageTable
	nop

	# check is fault is to address above the PT
	# la   $a1, ( (_PT+2*4096) + (x_INST_BASE_ADDR >>13)*16)

	# slt  $a2, $a1, $a0	# a2 <- (badVAddr > PageTable_top)
	# bne  $a2, $zero, L_chks	#   fault is not to PageTable
	# nop
	
	# this is same code as in start.s
        # get physical page number for two pages at the bottom of PageTable
        la    $a0, ( MIDDLE_RAM >>13 )<<13
        mtc0  $a0, c0_entryhi           # tag for bottom double-page

        la    $a0, ( (MIDDLE_RAM + 0*4096) >>12 )<<6
        ori   $a1, $a0, 0b00000000000000000000000000000111 # ccc=0, d,v,g1
        mtc0  $a1, c0_entrylo0          # bottom page (even)

        la    $a0, ( (MIDDLE_RAM + 1*4096) >>12 )<<6
        ori   $a1, $a0, 0b00000000000000000000000000000111 # ccc=0, d,v,g1
        mtc0  $a1, c0_entrylo1          # bottom page + 1 (odd)

        # and write it to TLB[4]
        li    $k0, 4
        mtc0  $k0, c0_index
        tlbwi
	j     L_ret		# all work done, return
	nop

L_chks: andi $a0, $a0, 0x1000	# check if even or odd page
	nop
	beq  $a0, $zero, L_even
	mfc0 $a0, c0_context

L_odd:	j    L_test
	addi $a2, $a0, 12	# address for odd intLo1 entry
	
L_even: addi $a2, $a0, 4	# address for even intLo0 entry

L_test:	lw   $a1, 0($a2)	# get intLo{0,1}
	mfc0 $k0, c0_badvaddr	# get faulting address for printing
	andi $a0, $a1, TP_MAPPED # check if page is mapped
	nop
	beq  $a0, $zero, M_seg_fault	# no, abort simulation
	nop

	andi $a0, $a1, TP_SEC_MEM	# check if page is in secondary memory
	nop
	bne  $a0, $zero, M_sec_mem	# yes, abort simulation
	nop

	ori  $a1, $a1, TP_USED	# mark PT entry as used
	# sw   $a1, 0($a2)

	# if this were handler_TLBS, now is the time to also mark the
	#    PT entry as Modified
	# mark PT entry as used, writable and modified
	ori  $a1, $a1, (TP_USED | TP_MODIF | TP_WR_ABLE)
	sw   $a1, 0($a2)
	
L_ret:	lw   $a0,  9*4($k1)	# nothing else to do, return
	lw   $a1, 10*4($k1)
	lw   $a2, 11*4($k1)
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
	srl  $a0, $a0, 13	# clear out in-page address bits
	sll  $a0, $a0, 13	# 
	mtc0 $a0, c0_entryhi
	nop
	tlbp			# probe the TLB
	nop
	mfc0 $a0, c0_index	# check for hit
	srl  $a0, $a0, 31	# keeo only MSbit
	nop
	bne  $a0, $zero, pu_miss # address not in TLB
	move $v0, $a0		# V_addr not in TLB

	tlbr			# read the entry
	li   $a0, -8192		# -8192 = 0xffff.e000
	mtc0 $a0, c0_entryhi	# and write an un-mapped address to tag

	addi $v0, $zero, -3	# -3 = 0xffff.fffd to clear valid bit
	mfc0 $a0, c0_entrylo0	# invalidate the mappings
	and  $a0, $v0, $a0
	mtc0 $a0, c0_entrylo0

	mfc0 $a0, c0_entrylo1
	and  $a0, $v0, $a0
	mtc0 $a0, c0_entrylo1
	move $v0, $zero		# V_addr was purged from TLB

	tlbwi			# write invalid mappings to TLB
	ehb
	
pu_miss: jr  $ra
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
	srl  $a0, $k0, 3
	mfc0 $a1, c0_cause
	mfc0 $a2, c0_epc
	mfc0 $a3, c0_badvaddr
	j    exception_report
	nop
	.end excp_report
