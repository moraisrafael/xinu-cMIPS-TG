/* getitem.c - getfirst, getlast, getitem */

#include <xinu.h>

/*------------------------------------------------------------------------
 *  getfirst  -  Remove a process from the front of a queue
 *------------------------------------------------------------------------
 */
pid32	getfirst(
	  qid32		q		/* ID of queue from which to	*/
	)				/* remove a process (assumed	*/
					/* valid with no check)		*/
{
	pid32	head;
	if (isempty(q)) { // ((queuetab[(q)].qnext) >= NPROC)
		return EMPTY;
	}

	head = queuehead(q);
	// kprintf("getfirst(%x)=%x h %x & %x\n",q,queuetab[head].qnext, head, &(queuetab[head]));
	return getitem(queuetab[head].qnext);
}

/*------------------------------------------------------------------------
 *  getlast  -  Remove a process from end of queue
 *------------------------------------------------------------------------
 */
pid32	getlast(
	  qid32		q		/* ID of queue from which to	*/
	)				/* remove a process (assumed	*/
					/* valid with no check)		*/
{
	pid32 tail;

	if (isempty(q)) {
		return EMPTY;
	}

	tail = queuetail(q);
	return getitem(queuetab[tail].qprev);
}

/*------------------------------------------------------------------------
 *  getitem  -  Remove a process from an arbitrary point in a queue
 *------------------------------------------------------------------------
 */
pid32	getitem(
	  pid32		pid		/* ID of process to remove	*/
	)
{
	pid32	prev, next;

	next = queuetab[pid].qnext;	/* following node in list	*/
	prev = queuetab[pid].qprev;	/* previous node in list	*/
	queuetab[prev].qnext = next;
	queuetab[next].qprev = prev;
	return pid;
}
