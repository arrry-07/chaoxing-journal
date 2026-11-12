package com.example.studyassistant

import java.util.concurrent.Executor
import java.util.concurrent.atomic.AtomicBoolean

/**
 * One engine's request-scoped lease ownership. Waiting never holds [monitor], and
 * control calls never enter the wait executor. Only unconfirmed grants expire;
 * a confirmed lease stays owned until explicit release or engine destruction.
 */
internal class BackgroundLeaseRequests(
    private val waitExecutor: Executor,
    private val dispatch: (() -> Unit) -> Unit,
    private val scheduleConfirmationTimeout: (() -> Unit) -> (() -> Unit),
    private val onCleanupFailure: (Exception) -> Unit = {},
) {
    interface Reply {
        fun success(value: Any?)
        fun error(error: Exception)
    }

    private data class Key(val sync: Boolean, val owner: String, val requestId: String)
    private class Request(val key: Key) {
        val cancelled = AtomicBoolean(false)
        var held = false
        var confirmed = false
        var finished = false
        var cancelTimeout: (() -> Unit)? = null
    }

    private val monitor = Any()
    // Keep terminal request ids until this engine dies: a delayed duplicate must
    // not acquire a second layer after cancellation/release.
    private val requests = mutableMapOf<Key, Request>()
    private var destroyed = false

    fun acquireSync(
        accountHash: String,
        requestId: String,
        readState: () -> Map<String, Any?>,
        reply: Reply,
    ) {
        acquire(Key(true, accountHash, requestId), reply, readState)
    }

    fun acquireWrite(owner: String, requestId: String, reply: Reply) {
        acquire(Key(false, owner, requestId), reply) { emptyMap() }
    }

    fun confirmSync(accountHash: String, requestId: String): Boolean =
        confirm(Key(true, accountHash, requestId))

    fun confirmWrite(owner: String, requestId: String): Boolean =
        confirm(Key(false, owner, requestId))

    fun cancelSync(accountHash: String, requestId: String) =
        cancel(Key(true, accountHash, requestId))

    fun cancelWrite(owner: String, requestId: String) =
        cancel(Key(false, owner, requestId))

    fun releaseSync(accountHash: String, requestId: String) =
        release(Key(true, accountHash, requestId))

    fun releaseWrite(owner: String, requestId: String) =
        release(Key(false, owner, requestId))

    private fun acquire(key: Key, reply: Reply, readState: () -> Map<String, Any?>) {
        val request = synchronized(monitor) {
            check(!destroyed) { "提醒引擎已销毁" }
            val existing = requests[key]
            // A Worker reuses its lease owner for several syncs in one engine;
            // allow the id again only after the previous request terminated.
            check(existing == null || existing.finished) { "租约 requestId 已使用" }
            Request(key).also { requests[key] = it }
        }
        val replied = AtomicBoolean(false)
        fun deliver(error: Exception?, waited: Boolean, state: Map<String, Any?>) {
            dispatch {
                if (replied.compareAndSet(false, true)) {
                    if (error != null) {
                        reply.error(error)
                    } else {
                        val acquired = synchronized(monitor) {
                            !destroyed && request.held && !request.cancelled.get()
                        }
                        reply.success(
                            if (key.sync) state + mapOf("acquired" to acquired, "waited" to waited)
                            else acquired,
                        )
                    }
                }
            }
        }
        try {
            waitExecutor.execute {
                var waited = false
                try {
                    val acquired = if (key.sync) {
                        BackgroundExecutionCoordinator.acquireSync(
                            key.owner,
                            key.requestId,
                            120_000L,
                            request.cancelled::get,
                        ).let {
                            waited = it.waited
                            it.acquired
                        }
                    } else {
                        BackgroundExecutionCoordinator.acquireWrite(
                            key.owner,
                            60_000L,
                            request.cancelled::get,
                        )
                    }
                    val needsState = synchronized(monitor) {
                        request.held = acquired
                        if (destroyed || request.cancelled.get()) {
                            releaseHeld(request)
                            false
                        } else if (acquired) {
                            request.cancelTimeout = scheduleConfirmationTimeout {
                                synchronized(monitor) {
                                    if (!request.confirmed && !request.finished) {
                                        request.cancelled.set(true)
                                        try {
                                            finish(request)
                                        } catch (error: Exception) {
                                            onCleanupFailure(error)
                                        }
                                    }
                                }
                            }
                            true
                        } else {
                            request.finished = true
                            false
                        }
                    }
                    // readState can fail after acquisition. Its catch below owns
                    // exactly this request's layer, including reentrant writes.
                    val state = if (needsState) readState() else emptyMap()
                    deliver(null, waited, state)
                } catch (error: Exception) {
                    synchronized(monitor) {
                        request.cancelled.set(true)
                        try {
                            finish(request)
                        } catch (cleanupError: Exception) {
                            error.addSuppressed(cleanupError)
                        }
                    }
                    deliver(error, waited, emptyMap())
                }
            }
        } catch (error: Exception) {
            synchronized(monitor) {
                request.cancelled.set(true)
                finish(request)
            }
            deliver(error, false, emptyMap())
        }
    }

    private fun confirm(key: Key): Boolean = synchronized(monitor) {
        val request = requests[key] ?: return@synchronized false
        if (destroyed || request.finished || !request.held || request.cancelled.get()) {
            return@synchronized false
        }
        request.cancelTimeout?.invoke()
        request.cancelTimeout = null
        request.confirmed = true
        true
    }

    private fun cancel(key: Key) {
        synchronized(monitor) {
            // A cancel that beats a queued acquire remains a terminal tombstone.
            val request = requests.getOrPut(key) { Request(key) }
            request.cancelled.set(true)
            finish(request)
        }
        BackgroundExecutionCoordinator.wakeWaiters()
    }

    private fun release(key: Key) {
        synchronized(monitor) {
            val request = requests[key] ?: return
            request.cancelled.set(true)
            finish(request)
        }
        BackgroundExecutionCoordinator.wakeWaiters()
    }

    private fun finish(request: Request) {
        request.cancelTimeout?.invoke()
        request.cancelTimeout = null
        releaseHeld(request)
        request.finished = true
    }

    private fun releaseHeld(request: Request) {
        if (!request.held) return
        if (request.key.sync) {
            BackgroundExecutionCoordinator.releaseSync(request.key.owner, request.key.requestId)
        } else {
            BackgroundExecutionCoordinator.releaseWrite(request.key.owner)
        }
        request.held = false
    }

    fun destroy() {
        synchronized(monitor) {
            if (destroyed) return
            destroyed = true
            requests.values.forEach { request ->
                request.cancelled.set(true)
                try {
                    finish(request)
                } catch (error: Exception) {
                    onCleanupFailure(error)
                }
            }
        }
        BackgroundExecutionCoordinator.wakeWaiters()
    }
}
