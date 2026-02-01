import { Activity, AlertTriangle, Clock, Zap } from 'lucide-react'

interface Metrics {
  totalRequests: number
  errorRate: number
  avgLatency: number
  activeTransactions: number
}

interface MetricsPanelProps {
  metrics: Metrics
}

export function MetricsPanel({ metrics }: MetricsPanelProps) {
  return (
    <div className="space-y-4">
      {/* Total Requests */}
      <div className="bg-slate-800 rounded-lg p-4 border border-slate-700">
        <div className="flex items-center gap-3 mb-2">
          <Activity className="w-5 h-5 text-blue-400" />
          <span className="text-slate-400 text-sm">Total Requests</span>
        </div>
        <div className="text-2xl font-bold text-white">
          {metrics.totalRequests.toLocaleString()}
        </div>
        <div className="text-xs text-slate-500 mt-1">Last 5 minutes</div>
      </div>

      {/* Error Rate */}
      <div className="bg-slate-800 rounded-lg p-4 border border-slate-700">
        <div className="flex items-center gap-3 mb-2">
          <AlertTriangle className={`w-5 h-5 ${metrics.errorRate > 5 ? 'text-red-400' : 'text-green-400'}`} />
          <span className="text-slate-400 text-sm">Error Rate</span>
        </div>
        <div className={`text-2xl font-bold ${metrics.errorRate > 5 ? 'text-red-400' : 'text-green-400'}`}>
          {metrics.errorRate.toFixed(1)}%
        </div>
        <div className="mt-2 h-2 bg-slate-700 rounded-full overflow-hidden">
          <div
            className={`h-full transition-all ${metrics.errorRate > 5 ? 'bg-red-500' : 'bg-green-500'}`}
            style={{ width: `${Math.min(metrics.errorRate, 100)}%` }}
          />
        </div>
      </div>

      {/* Average Latency */}
      <div className="bg-slate-800 rounded-lg p-4 border border-slate-700">
        <div className="flex items-center gap-3 mb-2">
          <Clock className={`w-5 h-5 ${metrics.avgLatency > 1000 ? 'text-yellow-400' : 'text-green-400'}`} />
          <span className="text-slate-400 text-sm">Avg Latency</span>
        </div>
        <div className={`text-2xl font-bold ${metrics.avgLatency > 1000 ? 'text-yellow-400' : 'text-white'}`}>
          {metrics.avgLatency.toFixed(0)}ms
        </div>
        <div className="text-xs text-slate-500 mt-1">
          {metrics.avgLatency > 1000 ? 'Elevated latency' : 'Normal'}
        </div>
      </div>

      {/* Active Transactions */}
      <div className="bg-slate-800 rounded-lg p-4 border border-slate-700">
        <div className="flex items-center gap-3 mb-2">
          <Zap className="w-5 h-5 text-purple-400" />
          <span className="text-slate-400 text-sm">Active Transactions</span>
        </div>
        <div className="text-2xl font-bold text-white">
          {metrics.activeTransactions}
        </div>
        <div className="text-xs text-slate-500 mt-1">In progress</div>
      </div>
    </div>
  )
}
