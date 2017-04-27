// Testing the external counter is difficult because it counts clock cycles
// rather than instructions -- if the io/instruction latencies change then
// the simulation output also changes and comparisons become impossible.

#include "cMIPS.h"

#define FALSE (0==1)
#define TRUE  ~(FALSE)

#define N 4
#define CNT_VALUE 0x40000040    // set count to 64 cycles

void main(void) {
  int i, increased, new, old, newValue;

  newValue = CNT_VALUE;

  for (i=0; i < N; i++) {       // repeat N rounds
    print(i);                   // print number of round

    newValue = CNT_VALUE + (i<<3);
    startCounter(newValue, 0);  // num cycles increases with i, no interrupts

    increased = TRUE;
    old = 0;

    do {

      if ( (new=readCounter()) > old) {
	increased = increased & TRUE;
	old = new;
	// print(new);          // print current count, not for automated tests
      } else {
	increased = FALSE;
      }

    } while ( (readCounter() & 0x3fffffff) < (newValue & 0x3ffffff) );
    // are we done yet?

    if (increased) {
      to_stdout('o');
      to_stdout('k');
    } else {
      to_stdout('e');
      to_stdout('r');
      to_stdout('r');
    }

    to_stdout('\n');
  }

}
