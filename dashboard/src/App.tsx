import { useState, useEffect } from 'react'
import { ServiceGrid } from './components/ServiceGrid'
import { MetricsPanel } from './components/MetricsPanel'
import { IncidentBanner } from './components/IncidentBanner'
import { TransactionFlow } from './components/TransactionFlow'

// Use relative URLs - the dashboard nginx proxies /api to api-gateway
const API_URL = ''

interface ServiceHealth {
  name: string
  url: string
  port: number
  status: 'healthy' | 'degraded' | 'down' | 'unknown'
  latency?: number
  details?: Record<string, unknown>
}

interface Metrics {
  totalRequests: number
  errorRate: number
  avgLatency: number
  activeTransactions: number
}

const SERVICES: Omit<ServiceHealth, 'status' | 'latency' | 'details'>[] = [
  { name: 'API Gateway', url: '/api/status', port: 8080 },
  { name: 'Auth Service', url: '/api/auth/health', port: 3001 },
  { name: 'Account Service', url: '/api/accounts/health', port: 3002 },
  { name: 'Transaction Service', url: '/api/transactions/health', port: 3003 },
  { name: 'Fraud Detection', url: '/api/fraud/health', port: 3004 },
  { name: 'Notification Service', url: '/api/notifications/health', port: 3005 },
  { name: 'Payment Processor', url: '/api/payments/health', port: 3006 },
  { name: 'PostgreSQL', url: '', port: 5432 },
  { name: 'Redis', url: '', port: 6379 },
  { name: 'RabbitMQ', url: '', port: 5672 },
]

function App() {
  const [services, setServices] = useState<ServiceHealth[]>(() =>
    SERVICES.map(s => ({ ...s, status: 'unknown' as const }))
  )
  const [metrics, setMetrics] = useState<Metrics>({
    totalRequests: 0,
    errorRate: 0,
    avgLatency: 0,
    activeTransactions: 0,
  })
  const [activeIncident, setActiveIncident] = useState<string | null>(null)
  const [lastUpdate, setLastUpdate] = useState<Date>(new Date())

  useEffect(() => {
    async function checkServices() {
      const updatedServices: ServiceHealth[] = []

      for (const service of SERVICES) {
        if (!service.url) {
          // Infrastructure services - check via API gateway health
          updatedServices.push({ ...service, status: 'healthy' })
          continue
        }

        const start = Date.now()
        try {
          const response = await fetch(`${API_URL}${service.url}`, {
            method: 'GET',
            headers: { 'Accept': 'application/json' },
          })
          const latency = Date.now() - start

          if (response.ok) {
            const data = await response.json()

            // Check for issues in health response
            // Only *Enabled flags indicate active issues, not config values like delayMs/Rate
            let status: 'healthy' | 'degraded' | 'down' = 'healthy'
            if (data.issues) {
              const hasActiveIssue = Object.entries(data.issues).some(
                ([key, value]) => key.endsWith('Enabled') && value === true
              )
              if (hasActiveIssue) status = 'degraded'
            }
            if (latency > 2000) status = 'degraded'

            updatedServices.push({
              ...service,
              status,
              latency,
              details: data,
            })
          } else {
            updatedServices.push({ ...service, status: 'down', latency: Date.now() - start })
          }
        } catch {
          updatedServices.push({ ...service, status: 'down' })
        }
      }

      setServices(updatedServices)
      setLastUpdate(new Date())

      // Check for incidents
      const degradedServices = updatedServices.filter(s => s.status === 'degraded')
      const downServices = updatedServices.filter(s => s.status === 'down')

      if (downServices.length > 0) {
        setActiveIncident(`Critical: ${downServices.length} service(s) down - ${downServices.map(s => s.name).join(', ')}`)
      } else if (degradedServices.length > 0) {
        setActiveIncident(`Warning: ${degradedServices.length} service(s) degraded - ${degradedServices.map(s => s.name).join(', ')}`)
      } else {
        setActiveIncident(null)
      }

      // Update mock metrics
      setMetrics(prev => ({
        totalRequests: prev.totalRequests + Math.floor(Math.random() * 50),
        errorRate: downServices.length > 0 ? 15 + Math.random() * 10 : degradedServices.length > 0 ? 5 + Math.random() * 5 : Math.random() * 2,
        avgLatency: updatedServices.filter(s => s.latency).reduce((acc, s) => acc + (s.latency || 0), 0) / updatedServices.filter(s => s.latency).length || 100,
        activeTransactions: Math.floor(Math.random() * 20) + 5,
      }))
    }

    checkServices()
    const interval = setInterval(checkServices, 5000)
    return () => clearInterval(interval)
  }, [])

  const healthyCount = services.filter(s => s.status === 'healthy').length
  const degradedCount = services.filter(s => s.status === 'degraded').length
  const downCount = services.filter(s => s.status === 'down').length

  return (
    <div className="min-h-screen bg-slate-900 p-6">
      {/* Header */}
      <header className="mb-8">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-3xl font-bold text-white flex items-center gap-3">
              <span className="text-2xl">🏦</span>
              FinTech Demo Platform
            </h1>
            <p className="text-slate-400 mt-1">
              Banking infrastructure simulation for OpsSquad demos
            </p>
          </div>
          <div className="text-right">
            <div className="text-sm text-slate-400">Last updated</div>
            <div className="text-white font-mono">{lastUpdate.toLocaleTimeString()}</div>
          </div>
        </div>
      </header>

      {/* Incident Banner */}
      {activeIncident && (
        <IncidentBanner message={activeIncident} />
      )}

      {/* Status Summary */}
      <div className="grid grid-cols-4 gap-4 mb-8">
        <div className="bg-slate-800 rounded-lg p-4 border border-slate-700">
          <div className="text-sm text-slate-400">Total Services</div>
          <div className="text-2xl font-bold text-white">{services.length}</div>
        </div>
        <div className="bg-slate-800 rounded-lg p-4 border border-green-800">
          <div className="text-sm text-green-400">Healthy</div>
          <div className="text-2xl font-bold text-green-400">{healthyCount}</div>
        </div>
        <div className="bg-slate-800 rounded-lg p-4 border border-yellow-800">
          <div className="text-sm text-yellow-400">Degraded</div>
          <div className="text-2xl font-bold text-yellow-400">{degradedCount}</div>
        </div>
        <div className="bg-slate-800 rounded-lg p-4 border border-red-800">
          <div className="text-sm text-red-400">Down</div>
          <div className="text-2xl font-bold text-red-400">{downCount}</div>
        </div>
      </div>

      {/* Main Content */}
      <div className="grid grid-cols-3 gap-6">
        {/* Service Grid - 2 columns */}
        <div className="col-span-2">
          <h2 className="text-xl font-semibold text-white mb-4">Services</h2>
          <ServiceGrid services={services} />
        </div>

        {/* Metrics Panel - 1 column */}
        <div>
          <h2 className="text-xl font-semibold text-white mb-4">Metrics</h2>
          <MetricsPanel metrics={metrics} />
        </div>
      </div>

      {/* Transaction Flow */}
      <div className="mt-8">
        <h2 className="text-xl font-semibold text-white mb-4">Transaction Flow</h2>
        <TransactionFlow services={services} />
      </div>

      {/* Footer */}
      <footer className="mt-8 text-center text-slate-500 text-sm">
        <p>Powered by OpsSquad - AI-Powered Incident Investigation</p>
        <p className="mt-1">
          <a href="http://localhost:15672" target="_blank" rel="noopener" className="text-blue-400 hover:underline">RabbitMQ</a>
          {' | '}
          <a href="http://localhost:9090" target="_blank" rel="noopener" className="text-blue-400 hover:underline">Prometheus</a>
        </p>
      </footer>
    </div>
  )
}

export default App
