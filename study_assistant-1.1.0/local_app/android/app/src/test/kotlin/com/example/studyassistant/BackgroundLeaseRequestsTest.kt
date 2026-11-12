package com.example.studyassistant

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

class BackgroundLeaseRequestsTest {
    private val workers = Executors.newCachedThreadPool()
    private val timers = mutableListOf<() -> Unit>()
    private val owners = mutableListOf<String>()
    private val registries = mutableListOf<BackgroundLeaseRequests>()

    @After
    fun tearDown() {
        registries.forEach { it.destroy() }
        owners.forEach { BackgroundExecutionCoordinator.releaseAllForOwner(it) }
        workers.shutdownNow()
        assertTrue(workers.awaitTermination(3, TimeUnit.SECONDS))
    }

    @Test
    fun acquiredLeaseReadFailureReleasesAndReplies() {
        val registry = registry()
        val account = owner()
        val request = owner()
        val reply = Reply()
        registry.acquireSync(account, request, { throw IllegalStateException("read failed") }, reply)
        reply.await()
        assertEquals(1, reply.count.get())
        assertTrue(reply.error.get()?.message!!.contains("read failed"))
        assertFalse(registry.confirmSync(account, request))
        val next = owner()
        assertTrue(BackgroundExecutionCoordinator.acquireSync(account, next, 0).acquired)
        BackgroundExecutionCoordinator.releaseSync(account, next)
    }

    @Test
    fun timedOutAcquisitionCannotLeakLateGrant() {
        val dispatches = mutableListOf<() -> Unit>()
        val registry = registry(dispatch = { synchronized(dispatches) { dispatches.add(it) } })
        val owner = owner()
        val request = owner()
        val reply = Reply()
        val queued = CountDownLatch(1)
        registry.acquireWrite(owner, request, object : BackgroundLeaseRequests.Reply {
            override fun success(value: Any?) { reply.success(value) }
            override fun error(error: Exception) { reply.error(error) }
        })
        // Wait for the acquisition result to be queued, but do not deliver it to Dart.
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(2)
        while (synchronized(dispatches) { dispatches.isEmpty() } && System.nanoTime() < deadline) {
            Thread.yield()
        }
        synchronized(dispatches) { assertEquals(1, dispatches.size) }
        fireTimers()
        assertFalse(registry.confirmWrite(owner, request))
        synchronized(dispatches) { dispatches.removeAt(0) }.invoke()
        reply.await()
        assertEquals(false, reply.value.get())
        assertEquals(1, reply.count.get())
        val next = owner()
        assertTrue(BackgroundExecutionCoordinator.acquireWrite(next, 0))
    }

    @Test
    fun confirmationRemovesDeadlineButDoesNotExpireRunningLease() {
        val registry = registry()
        val owner = owner()
        val request = owner()
        val reply = Reply()
        registry.acquireWrite(owner, request, reply)
        reply.await()
        assertEquals(true, reply.value.get())
        assertTrue(registry.confirmWrite(owner, request))
        assertTrue(registry.confirmWrite(owner, request))
        fireTimers()
        assertFalse(BackgroundExecutionCoordinator.acquireWrite(owner(), 0))
        registry.releaseWrite(owner, request)
        registry.releaseWrite(owner, request)
        assertTrue(BackgroundExecutionCoordinator.acquireWrite(owner(), 0))
    }

    @Test
    fun cancelDoesNotReleaseAnotherRequestOrWorkerOuterLayer() {
        val registry = registry()
        val owner = owner()
        assertTrue(BackgroundExecutionCoordinator.acquireWrite(owner, 0))
        val first = owner()
        val second = owner()
        val firstReply = Reply()
        val secondReply = Reply()
        registry.acquireWrite(owner, first, firstReply)
        firstReply.await()
        assertTrue(registry.confirmWrite(owner, first))
        registry.acquireWrite(owner, second, secondReply)
        secondReply.await()
        registry.cancelWrite(owner, second)
        registry.cancelWrite(owner, second)
        registry.releaseWrite(owner(), first)
        assertTrue(registry.confirmWrite(owner, first))
        assertFalse(BackgroundExecutionCoordinator.acquireWrite(owner(), 0))
        registry.releaseWrite(owner, first)
        assertFalse(BackgroundExecutionCoordinator.acquireWrite(owner(), 0))
        BackgroundExecutionCoordinator.releaseWrite(owner)
        assertTrue(BackgroundExecutionCoordinator.acquireWrite(owner(), 0))
    }

    @Test
    fun destroyReleasesOnlyItsOwnConfirmedLayers() {
        val registry = registry()
        val owner = owner()
        val request = owner()
        assertTrue(BackgroundExecutionCoordinator.acquireWrite(owner, 0))
        val reply = Reply()
        registry.acquireWrite(owner, request, reply)
        reply.await()
        assertTrue(registry.confirmWrite(owner, request))
        registry.destroy()
        registry.destroy()
        assertFalse(registry.confirmWrite(owner, request))
        assertFalse(BackgroundExecutionCoordinator.acquireWrite(owner(), 0))
        BackgroundExecutionCoordinator.releaseWrite(owner)
        assertTrue(BackgroundExecutionCoordinator.acquireWrite(owner(), 0))
    }

    @Test
    fun destroyedWaitingOwnerNeverReceivesLease() {
        val blocker = owner()
        val owner = owner()
        assertTrue(BackgroundExecutionCoordinator.acquireWrite(blocker, 0))
        val entered = CountDownLatch(1)
        val registry = registry(executor = Executor { task ->
            workers.execute {
                entered.countDown()
                task.run()
            }
        })
        val reply = Reply()
        registry.acquireWrite(owner, owner(), reply)
        assertTrue(entered.await(1, TimeUnit.SECONDS))
        registry.destroy()
        BackgroundExecutionCoordinator.releaseWrite(blocker)
        reply.await()
        assertEquals(false, reply.value.get())
        assertEquals(1, reply.count.get())
        assertTrue(BackgroundExecutionCoordinator.acquireWrite(owner(), 0))
    }

    @Test
    fun cancelledSyncReadCannotDeliverOrReleaseNewRequest() {
        val registry = registry()
        val account = owner()
        val request = owner()
        val reading = CountDownLatch(1)
        val continueRead = CountDownLatch(1)
        val reply = Reply()
        registry.acquireSync(account, request, {
            reading.countDown()
            assertTrue(continueRead.await(2, TimeUnit.SECONDS))
            emptyMap()
        }, reply)
        try {
            assertTrue(reading.await(1, TimeUnit.SECONDS))
            registry.cancelSync(account, request)
            registry.cancelSync(account, request)
            val next = owner()
            assertTrue(BackgroundExecutionCoordinator.acquireSync(account, next, 0).acquired)
            continueRead.countDown()
            reply.await()
            assertEquals(false, (reply.value.get() as Map<*, *>)["acquired"])
            assertFalse(registry.confirmSync(account, request))
            assertFalse(BackgroundExecutionCoordinator.acquireSync(account, owner(), 0).acquired)
            BackgroundExecutionCoordinator.releaseSync(account, next)
        } finally {
            continueRead.countDown()
        }
    }

    @Test
    fun cancellationBeforeQueuedWorkerStartsPreventsGrant() {
        val queued = mutableListOf<Runnable>()
        val registry = registry(executor = Executor { queued.add(it) })
        val owner = owner()
        val request = owner()
        val reply = Reply()
        registry.acquireWrite(owner, request, reply)
        registry.cancelWrite(owner, request)
        queued.single().run()
        reply.await()
        assertEquals(false, reply.value.get())
        assertFalse(registry.confirmWrite(owner, request))
        assertTrue(BackgroundExecutionCoordinator.acquireWrite(owner(), 0))
    }

    @Test
    fun waitingAcquisitionDoesNotQueueControlRelease() {
        val registry = registry()
        val firstOwner = owner()
        val firstRequest = owner()
        val first = Reply()
        registry.acquireWrite(firstOwner, firstRequest, first)
        first.await()
        assertTrue(registry.confirmWrite(firstOwner, firstRequest))
        val nextOwner = owner()
        val nextRequest = owner()
        val next = Reply()
        registry.acquireWrite(nextOwner, nextRequest, next)
        registry.releaseWrite(firstOwner, firstRequest)
        next.await()
        assertEquals(true, next.value.get())
        assertTrue(registry.confirmWrite(nextOwner, nextRequest))
    }

    @Test
    fun releasedRequestIdCannotBeReusedAndLateControlsCannotReleaseNextLayer() {
        val registry = registry()
        val owner = owner()
        val request = owner()
        val first = Reply()
        registry.acquireWrite(owner, request, first)
        first.await()
        assertTrue(registry.confirmWrite(owner, request))
        registry.releaseWrite(owner, request)

        val secondRequest = owner()
        val second = Reply()
        registry.acquireWrite(owner, secondRequest, second)
        second.await()
        assertEquals(true, second.value.get())
        assertTrue(registry.confirmWrite(owner, secondRequest))
        assertFalse(registry.confirmWrite(owner, request))
        registry.cancelWrite(owner, request)
        registry.releaseWrite(owner, request)
        try {
            registry.acquireWrite(owner, request, Reply())
            throw AssertionError("终态 requestId 不得重新授予")
        } catch (_: IllegalStateException) {
            // Delayed acquire and old controls must not touch the new layer.
        }
        assertFalse(BackgroundExecutionCoordinator.acquireWrite(owner(), 0))
        registry.releaseWrite(owner, secondRequest)
        assertTrue(BackgroundExecutionCoordinator.acquireWrite(owner(), 0))
    }

    @Test
    fun cancelBeforeAcquireCreatesPermanentSyncAndWriteTombstones() {
        val registry = registry()
        val account = owner()
        val request = owner()
        registry.cancelSync(account, request)
        registry.cancelWrite(account, request)
        for (sync in listOf(true, false)) {
            try {
                if (sync) registry.acquireSync(account, request, { emptyMap() }, Reply())
                else registry.acquireWrite(account, request, Reply())
                throw AssertionError("取消先到时不得复活")
            } catch (_: IllegalStateException) {
                // The request key remains terminal until engine destruction.
            }
        }
        assertFalse(registry.confirmSync(account, request))
        assertFalse(registry.confirmWrite(account, request))
    }

    private fun registry(
        executor: Executor = workers,
        dispatch: (() -> Unit) -> Unit = { it() },
    ) = BackgroundLeaseRequests(
        waitExecutor = executor,
        dispatch = dispatch,
        scheduleConfirmationTimeout = { task ->
            synchronized(timers) { timers.add(task) }
            // Intentionally keep the callback, simulating an already-dispatched timeout race.
            val cancel: () -> Unit = {}
            cancel
        },
    ).also { registries.add(it) }

    private fun fireTimers() {
        val callbacks = synchronized(timers) { timers.toList().also { timers.clear() } }
        callbacks.forEach { it() }
    }

    private fun owner() = "lease-test:${UUID.randomUUID()}".also { owners.add(it) }

    private class Reply : BackgroundLeaseRequests.Reply {
        val count = AtomicInteger()
        val value = AtomicReference<Any?>()
        val error = AtomicReference<Exception?>()
        private val finished = CountDownLatch(1)
        override fun success(value: Any?) {
            count.incrementAndGet()
            this.value.set(value)
            finished.countDown()
        }
        override fun error(error: Exception) {
            count.incrementAndGet()
            this.error.set(error)
            finished.countDown()
        }
        fun await() = assertTrue("租约请求没有应答", finished.await(2, TimeUnit.SECONDS))
    }
}
