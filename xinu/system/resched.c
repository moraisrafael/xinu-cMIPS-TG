/* resched.c - resched */

#include <xinu.h>

/*------------------------------------------------------------------------
 *  resched  -  Reschedule processor to highest priority eligible process
 *------------------------------------------------------------------------
 */
void	resched(void)		/* assumes interrupts are disabled	*/
{
	struct procent *ptold;	/* ptr to table entry for old process	*/
	struct procent *ptnew;	/* ptr to table entry for new process	*/

	/* If rescheduling is deferred, record attempt and return */

	if (Defer.ndefers > 0) {
		Defer.attempt = TRUE;
		return;
	}

	/* Point to process table entry for the current (old) process */

	ptold = &proctab[currpid];

	if (ptold->prstate == PR_CURR) {  /* process remains running */
		if (ptold->prprio > firstkey(readylist)) {
                   // kprintf("keep %s pri %x\n", ptold->prname, ptold->prprio);
		   return;
		}

		/* Old process will no longer remain current */

		ptold->prstate = PR_READY;
		insert(currpid, readylist, ptold->prprio);
		// kprintf("pr %s ->q(%x) pri %x\n", ptold->prname, readylist, ptold->prprio);
	}

	/* Force context switch to highest priority ready process */

	currpid = dequeue(readylist);
	ptnew = &proctab[currpid];
	ptnew->prstate = PR_CURR;
	preempt = QUANTUM;		/* reset time slice for process	*/
        // kprintf("ctxtsw old=%s %x  new=%s %x\n",ptold->prname,ptold->prprio,
	// 	ptnew->prname, ptnew->prprio);
	ctxsw(&ptold->prstkptr, &ptnew->prstkptr);

	/* Old process returns here when resumed */

	return;
}
