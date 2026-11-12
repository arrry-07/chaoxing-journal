package com.example.studyassistant

import java.util.concurrent.ConcurrentHashMap

data class SyncLeaseAcquisition(
    val acquired: Boolean,
    val waited: Boolean,
)

/**
 * Process-wide coordination shared by the foreground engine, WorkManager
 * engines and alarm receivers. Locks are intentionally not time-expired while
 * an owner is still running. Engine destruction releases its owner explicitly.
 */
object BackgroundExecutionCoordinator {
    private class LeaseGate {
        val monitor = Object()
        var owner: String? = null
        var depth: Int = 0
        var acquisitionCounter: Long = 0
    }

    private val syncGates = ConcurrentHashMap<String, LeaseGate>()
    private val syncCompletions = ConcurrentHashMap<String, Long>()
    private val writeGate = LeaseGate()

    fun acquireSync(
        accountHash: String,
        requestId: String,
        timeoutMs: Long,
        isCancelled: () -> Boolean = { false },
    ): SyncLeaseAcquisition {
        val gate = syncGates.getOrPut(accountHash) { LeaseGate() }
        synchronized(gate.monitor) {
            if (isCancelled()) return SyncLeaseAcquisition(acquired = false, waited = false)
            if (gate.owner == requestId) {
                gate.depth++
                return SyncLeaseAcquisition(acquired = true, waited = false)
            }
            var waited = false
            val deadline = System.nanoTime() + java.util.concurrent.TimeUnit.MILLISECONDS.toNanos(timeoutMs)
            while (gate.owner != null) {
                if (isCancelled()) return SyncLeaseAcquisition(acquired = false, waited = waited)
                val remaining = java.util.concurrent.TimeUnit.NANOSECONDS.toMillis(deadline - System.nanoTime())
                if (remaining <= 0) {
                    return SyncLeaseAcquisition(acquired = false, waited = true)
                }
                waited = true
                gate.monitor.wait(remaining.coerceAtMost(1_000L))
            }
            if (isCancelled()) return SyncLeaseAcquisition(acquired = false, waited = waited)
            gate.owner = requestId
            gate.depth = 1
            gate.acquisitionCounter++
            return SyncLeaseAcquisition(acquired = true, waited = waited)
        }
    }

    fun releaseSync(accountHash: String, requestId: String) {
        val gate = syncGates[accountHash] ?: return
        synchronized(gate.monitor) {
            if (gate.owner != requestId) return
            gate.depth--
            if (gate.depth > 0) return
            gate.owner = null
            gate.depth = 0
            syncCompletions[accountHash] = System.currentTimeMillis()
            gate.monitor.notifyAll()
        }
    }

    fun lastSyncCompletion(accountHash: String): Long? =
        syncCompletions[accountHash]

    fun acquireWrite(
        owner: String,
        timeoutMs: Long = 60_000L,
        isCancelled: () -> Boolean = { false },
    ): Boolean {
        synchronized(writeGate.monitor) {
            if (isCancelled()) return false
            if (writeGate.owner == owner) {
                writeGate.depth++
                return true
            }
            val deadline = System.nanoTime() + java.util.concurrent.TimeUnit.MILLISECONDS.toNanos(timeoutMs)
            while (writeGate.owner != null) {
                if (isCancelled()) return false
                val remaining = java.util.concurrent.TimeUnit.NANOSECONDS.toMillis(deadline - System.nanoTime())
                if (remaining <= 0) return false
                writeGate.monitor.wait(remaining.coerceAtMost(1_000L))
            }
            if (isCancelled()) return false
            writeGate.owner = owner
            writeGate.depth = 1
            return true
        }
    }

    fun releaseWrite(owner: String) {
        synchronized(writeGate.monitor) {
            if (writeGate.owner != owner) return
            writeGate.depth--
            if (writeGate.depth > 0) return
            writeGate.owner = null
            writeGate.depth = 0
            writeGate.monitor.notifyAll()
        }
    }

    /** Cancellation predicates are checked under the same gate monitor as grants. */
    fun wakeWaiters() {
        syncGates.values.forEach { gate ->
            synchronized(gate.monitor) { gate.monitor.notifyAll() }
        }
        synchronized(writeGate.monitor) { writeGate.monitor.notifyAll() }
    }

    fun releaseAllForOwner(owner: String) {
        syncGates.forEach { (accountHash, gate) ->
            synchronized(gate.monitor) {
                if (gate.owner == owner) {
                    gate.owner = null
                    gate.depth = 0
                    syncCompletions[accountHash] = System.currentTimeMillis()
                    gate.monitor.notifyAll()
                }
            }
        }
        synchronized(writeGate.monitor) {
            if (writeGate.owner == owner) {
                writeGate.owner = null
                writeGate.depth = 0
                writeGate.monitor.notifyAll()
            }
        }
    }
}
