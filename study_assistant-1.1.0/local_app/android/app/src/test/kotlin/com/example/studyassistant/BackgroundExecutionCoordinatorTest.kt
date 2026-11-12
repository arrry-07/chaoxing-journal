package com.example.studyassistant

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class BackgroundExecutionCoordinatorTest {
    @Test
    fun waitingWriterDoesNotBlockOwnerRelease() {
        val owner = uniqueOwner()
        val waiter = uniqueOwner()
        val acquired = AtomicBoolean(false)
        val entered = CountDownLatch(1)
        val finished = CountDownLatch(1)
        val released = CountDownLatch(1)
        assertTrue(BackgroundExecutionCoordinator.acquireWrite(owner, 0))
        val thread = Thread {
            entered.countDown()
            try {
                acquired.set(BackgroundExecutionCoordinator.acquireWrite(waiter, 5_000))
            } finally {
                BackgroundExecutionCoordinator.releaseWrite(waiter)
                finished.countDown()
            }
        }
        thread.start()
        try {
            assertTrue(entered.await(1, TimeUnit.SECONDS))
            awaitWaiting(thread)
            Thread {
                BackgroundExecutionCoordinator.releaseWrite(owner)
                released.countDown()
            }.start()
            assertTrue("等待者不能阻塞持有者释放", released.await(1, TimeUnit.SECONDS))
            assertTrue(finished.await(1, TimeUnit.SECONDS))
            assertTrue(acquired.get())
        } finally {
            thread.interrupt()
            thread.join(6_000)
            BackgroundExecutionCoordinator.releaseAllForOwner(owner)
            BackgroundExecutionCoordinator.releaseAllForOwner(waiter)
        }
    }

    @Test
    fun sameOwnerIsReentrant() {
        val owner = uniqueOwner()
        val other = uniqueOwner()
        try {
            assertTrue(BackgroundExecutionCoordinator.acquireWrite(owner, 0))
            assertTrue(BackgroundExecutionCoordinator.acquireWrite(owner, 0))
            BackgroundExecutionCoordinator.releaseWrite(owner)
            assertFalse(BackgroundExecutionCoordinator.acquireWrite(other, 0))
            BackgroundExecutionCoordinator.releaseWrite(owner)
            assertTrue(BackgroundExecutionCoordinator.acquireWrite(other, 0))
        } finally {
            BackgroundExecutionCoordinator.releaseAllForOwner(owner)
            BackgroundExecutionCoordinator.releaseAllForOwner(other)
        }
    }

    @Test
    fun wrongOwnerCannotRelease() {
        val owner = uniqueOwner()
        val other = uniqueOwner()
        try {
            assertTrue(BackgroundExecutionCoordinator.acquireWrite(owner, 0))
            BackgroundExecutionCoordinator.releaseWrite(other)
            assertFalse(BackgroundExecutionCoordinator.acquireWrite(other, 0))
        } finally {
            BackgroundExecutionCoordinator.releaseAllForOwner(owner)
        }
    }

    @Test
    fun waitingWriterTimesOutWithoutReleasingOwner() {
        val owner = uniqueOwner()
        val other = uniqueOwner()
        try {
            assertTrue(BackgroundExecutionCoordinator.acquireWrite(owner, 0))
            assertFalse(BackgroundExecutionCoordinator.acquireWrite(other, 10))
            assertFalse(BackgroundExecutionCoordinator.acquireWrite(other, 0))
            BackgroundExecutionCoordinator.releaseAllForOwner(owner)
            assertTrue(BackgroundExecutionCoordinator.acquireWrite(other, 0))
        } finally {
            BackgroundExecutionCoordinator.releaseAllForOwner(owner)
            BackgroundExecutionCoordinator.releaseAllForOwner(other)
        }
    }

    @Test
    fun cancelledWaitingWriterNeverAcquires() {
        val owner = uniqueOwner()
        val waiter = uniqueOwner()
        val cancelled = AtomicBoolean(false)
        val acquired = AtomicBoolean(true)
        val finished = CountDownLatch(1)
        assertTrue(BackgroundExecutionCoordinator.acquireWrite(owner, 0))
        val thread = Thread {
            acquired.set(
                BackgroundExecutionCoordinator.acquireWrite(waiter, 5_000) { cancelled.get() },
            )
            finished.countDown()
        }
        thread.start()
        try {
            awaitWaiting(thread)
            cancelled.set(true)
            BackgroundExecutionCoordinator.wakeWaiters()
            assertTrue(finished.await(1, TimeUnit.SECONDS))
            assertFalse(acquired.get())
            BackgroundExecutionCoordinator.releaseWrite(owner)
            assertTrue(BackgroundExecutionCoordinator.acquireWrite(waiter, 0))
        } finally {
            cancelled.set(true)
            BackgroundExecutionCoordinator.wakeWaiters()
            thread.join(6_000)
            BackgroundExecutionCoordinator.releaseAllForOwner(owner)
            BackgroundExecutionCoordinator.releaseAllForOwner(waiter)
        }
    }

    @Test
    fun cancelledReentrantRequestDoesNotTakeAnotherLayer() {
        val owner = uniqueOwner()
        val other = uniqueOwner()
        val account = uniqueOwner()
        try {
            assertTrue(BackgroundExecutionCoordinator.acquireWrite(owner, 0))
            assertFalse(BackgroundExecutionCoordinator.acquireWrite(owner, 0) { true })
            assertTrue(BackgroundExecutionCoordinator.acquireSync(account, owner, 0).acquired)
            assertFalse(
                BackgroundExecutionCoordinator.acquireSync(account, owner, 0) { true }.acquired,
            )
            BackgroundExecutionCoordinator.releaseWrite(owner)
            BackgroundExecutionCoordinator.releaseSync(account, owner)
            assertTrue(BackgroundExecutionCoordinator.acquireWrite(other, 0))
            assertTrue(BackgroundExecutionCoordinator.acquireSync(account, other, 0).acquired)
        } finally {
            BackgroundExecutionCoordinator.releaseAllForOwner(owner)
            BackgroundExecutionCoordinator.releaseAllForOwner(other)
        }
    }

    private fun uniqueOwner() = "coordinator-test:${UUID.randomUUID()}"

    private fun awaitWaiting(thread: Thread) {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(1)
        while (thread.state != Thread.State.TIMED_WAITING && System.nanoTime() < deadline) {
            Thread.yield()
        }
        assertTrue("写请求必须已进入等待", thread.state == Thread.State.TIMED_WAITING)
    }
}
