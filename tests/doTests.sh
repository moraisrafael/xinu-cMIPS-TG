#!/bin/bash

# set -x

if [ ! -v tree ] ; then
  # you must set the location of the cMIPS root directory in the variable tree
  # tree=${HOME}/cmips-code/cMIPS
  # tree=${HOME}/cMIPS
  export tree="$(echo $PWD | sed -e 's:^\(/.*/xinu-cMIPS\)/.*:\1:')"
fi


# path to cross-compiler and binutils must be set to your installation
WORK_PATH=/home/soft/linux/mips/cross/bin
HOME_PATH=/opt/cross/bin

if [ -x /opt/cross/bin/mips-gcc ] ; then
    export PATH=$PATH:$HOME_PATH
elif [ -x /home/soft/linux/mips/cross/bin/mips-gcc ] ; then
    export PATH=$PATH:$WORK_PATH
else
    echo "\n\n\tPANIC: cross-compiler not installed\n\n" ; exit 1;
fi


bin=${tree}/bin
include=${tree}/include
srcVHDL=${tree}/vhdl

simulator=$tree/tb_cmips

usage() {
cat << EOF
usage:  $0 [options] 
        re-create simulator/model and simulate several test programs

OPTIONS:
   -h    Show this message
   -B    ignore blank space in comparing simulation to expected results
   -c    simulate only programs that are timing independent: can use caches
EOF
}

ignBLANKS=""
withCache=false

while true ; do

    case "$1" in
        -h | "-?") usage ; exit 1
            ;;
        -B) ignBLANKS="-B"
            ;;
        -c) withCache=true
            ;;
        "") break
            ;;
        *) usage ; echo "  invalid option: $1"; exit 1
            ;;
    esac
    shift
done

touch input.data serial.inp

a_FWD="fwdAddAddAddSw fwd_SW lwFWDsw slt32 slt_u_32 slt_s_32 reg0"
a_CAC="dCacheTst lhUshUCache lbUsbUCache lbsbCache dCacheTstH dCacheTstB"
a_BEQ="lw-bne bXtz sltbeq beq_dlySlot jr_dlySlot"
a_FUN="jaljr jr_2 jal_fun_jr jalr_jr bltzal_fun_jr"
a_OTH="mult div sll slr movz wsbh_seb extract insert"
a_BHW="lbsb lhsh lwsw lwswIncr swlw lwl_lwr"
a_MEM="lwSweepRAM"
a_CTR="teq_tne teq_jal teq_lw tlt_tlti tltu_tgeu eiDI ll_sc overflow counter"
a_COP="mtc0CAUSE2 mtc0EPC syscall break mfc0CONFIG badVAddr"


### xinu does not make use of the TLB:  mmu_double2"
# a_MMU="mmu_index mmu_tlbp mmu_tlbwr mmu_context"
# a_EXC="mmu_refill mmu_refill2 mmu_refill3 mmu_inval mmu_inval2 mmu_mod mmu_mod2 mmu_double"



## force an update of all include files with edMemory.sh
touch -t 201501010000.00 ../include/cMIPS.*

(cd $tree ; $bin/build.sh) || exit 1

rm -f *.simout *.elf

stoptime=20ms

if [ 0 = 0 ] ; then
    for F in $(echo $a_FWD $a_CAC $a_BEQ $a_FUN $a_OTH $a_BHW $a_MEM $a_CTR $a_COP $a_MMU $a_EXC $a_IOs);
    do
	$bin/assemble.sh ${F}.s
	${simulator} --ieee-asserts=disable --stop-time=$stoptime \
              2>/dev/null   >$F.simout
	diff $ignBLANKS -q $F.expected $F.simout
	if [ $? == 0 ] ; then
	    echo -e "\t $F"
	    rm -f ${F}.{elf,o,simout,map}
	else
	    echo -e "\n\n\tERROR in $F\n\n"
	    diff $F.expected $F.simout
	    exit 1
	fi
    done
fi


c_small="divmul fat fib sieve ccitt16 gcd matrix negcnt reduz rand"
c_types="xram sort-byte sort-half sort-int memcpy"
c_sorts="bubble insertion merge quick selection shell"

## the tests below MUST be run with FAKE CACHES
c_timing="extCounter extCounterInt"
c_uart="uarttx uartrx uart_irx"

## the tests below MUST be run with TRUE CACHES
# c_stats="sumSstats"

## the simulation time is far too long # c_2slow="dct-int"

stoptime=100ms

if [ $withCache = true ] ; then
  SIMULATE="$c_small $c_types $c_sorts"
else
  SIMULATE="$c_small $c_types $c_sorts $c_timing $c_uart"
  echo -e "\nabcdef\n012345\n" >serial.inp
  # make sure all memory latencies are ZERO
  # pack=$srcVHDL/packageWires.vhd
  # sed -i -e "/ROM_WAIT_STATES/s/ := \([0-9][0-9]*\);/ := 0;/" \
  #        -e "/RAM_WAIT_STATES/s/ := \([0-9][0-9]*\);/ := 0;/" \
  #        -e "/IO_WAIT_STATES/s/ := \([0-9][0-9]*\);/ := 0;/" $pack
fi

for F in $(echo "$SIMULATE" ) ; do 
    $bin/compile.sh -O 3 ${F}.c  || exit 1
    ${simulator} --ieee-asserts=disable --stop-time=$stoptime \
          2>/dev/null >$F.simout
    diff $ignBLANKS -q $F.expected $F.simout
    if [ $? == 0 ] ; then
	echo -e "\t $F"
	rm -f ${F}.{elf,s,o,simout,map}
    else
	echo -e "\n\n\tERROR in $F\n\n"
	diff $F.expected $F.simout
	exit 1
    fi
done

