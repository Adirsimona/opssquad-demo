import { Server, Database, Shield, Bell, CreditCard, Users, Zap, Lock, MessageSquare, Globe } from 'lucide-react'

interface ServiceHealth {
  name: string
  url: string
  port: number
  status: 'healthy' | 'degraded' | 'down' | 'unknown'
  latency?: number
  details?: Record<string, unknown>
}

interface ServiceCardProps {
  service: ServiceHealth
}

const SERVICE_ICONS: Record<string, typeof Server> = {
  'API Gateway': Globe,
  'Auth Service': Lock,
  'Account Service': Users,
  'Transaction Service': Zap,
  'Fraud Detection': Shield,
  'Notification Service': Bell,
  'Payment Processor': CreditCard,
  'PostgreSQL': Database,
  'Redis': Database,
  'RabbitMQ': MessageSquare,
}

const STATUS_COLORS = {
  healthy: 'bg-green-500',
  degraded: 'bg-yellow-500',
  down: 'bg-red-500',
  unknown: 'bg-gray-500',
}

const STATUS_BORDERS = {
  healthy: 'border-green-800',
  degraded: 'border-yellow-800',
  down: 'border-red-800',
  unknown: 'border-gray-700',
}

const STATUS_TEXT = {
  healthy: 'text-green-400',
  degraded: 'text-yellow-400',
  down: 'text-red-400',
  unknown: 'text-gray-400',
}

export function ServiceCard({ service }: ServiceCardProps) {
  const Icon = SERVICE_ICONS[service.name] || Server
  const issues = service.details?.issues as Record<string, unknown> | undefined

  return (
    <div className={`bg-slate-800 rounded-lg p-4 border ${STATUS_BORDERS[service.status]} transition-all hover:bg-slate-750`}>
      <div className="flex items-start justify-between mb-3">
        <div className="flex items-center gap-2">
          <Icon className={`w-5 h-5 ${STATUS_TEXT[service.status]}`} />
          <h3 className="font-medium text-white text-sm">{service.name}</h3>
        </div>
        <div className={`w-3 h-3 rounded-full ${STATUS_COLORS[service.status]} ${service.status === 'down' ? 'pulse-glow' : ''}`} />
      </div>

      <div className="space-y-2 text-sm">
        <div className="flex justify-between">
          <span className="text-slate-400">Port</span>
          <span className="text-white font-mono">{service.port}</span>
        </div>

        {service.latency !== undefined && (
          <div className="flex justify-between">
            <span className="text-slate-400">Latency</span>
            <span className={`font-mono ${service.latency > 1000 ? 'text-yellow-400' : 'text-white'}`}>
              {service.latency}ms
            </span>
          </div>
        )}

        <div className="flex justify-between">
          <span className="text-slate-400">Status</span>
          <span className={`font-medium capitalize ${STATUS_TEXT[service.status]}`}>
            {service.status}
          </span>
        </div>
      </div>

      {/* Show active issues */}
      {issues && Object.entries(issues).some(([, v]) => v === true || (typeof v === 'number' && v > 0)) && (
        <div className="mt-3 pt-3 border-t border-slate-700">
          <div className="text-xs text-yellow-400 font-medium mb-1">Active Issues</div>
          <div className="space-y-1">
            {Object.entries(issues).map(([key, value]) => {
              if (value === true || (typeof value === 'number' && value > 0)) {
                return (
                  <div key={key} className="text-xs text-slate-400">
                    {key.replace(/([A-Z])/g, ' $1').replace(/^./, str => str.toUpperCase())}
                    {typeof value === 'number' && `: ${value}`}
                  </div>
                )
              }
              return null
            })}
          </div>
        </div>
      )}
    </div>
  )
}
