import { ServiceCard } from './ServiceCard'

interface ServiceHealth {
  name: string
  url: string
  port: number
  status: 'healthy' | 'degraded' | 'down' | 'unknown'
  latency?: number
  details?: Record<string, unknown>
}

interface ServiceGridProps {
  services: ServiceHealth[]
}

export function ServiceGrid({ services }: ServiceGridProps) {
  return (
    <div className="grid grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
      {services.map((service) => (
        <ServiceCard key={service.name} service={service} />
      ))}
    </div>
  )
}
