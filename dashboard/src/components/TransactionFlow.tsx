interface ServiceHealth {
  name: string
  status: 'healthy' | 'degraded' | 'down' | 'unknown'
}

interface TransactionFlowProps {
  services: ServiceHealth[]
}

const STATUS_COLORS = {
  healthy: '#22c55e',
  degraded: '#eab308',
  down: '#ef4444',
  unknown: '#6b7280',
}

export function TransactionFlow({ services }: TransactionFlowProps) {
  const getServiceStatus = (name: string) => {
    const service = services.find(s => s.name === name)
    return service?.status || 'unknown'
  }

  const nodes = [
    { id: 'client', label: 'Client', x: 50, y: 150 },
    { id: 'gateway', label: 'API Gateway', x: 150, y: 150, service: 'API Gateway' },
    { id: 'auth', label: 'Auth', x: 280, y: 80, service: 'Auth Service' },
    { id: 'account', label: 'Account', x: 280, y: 150, service: 'Account Service' },
    { id: 'transaction', label: 'Transaction', x: 280, y: 220, service: 'Transaction Service' },
    { id: 'fraud', label: 'Fraud', x: 420, y: 150, service: 'Fraud Detection' },
    { id: 'payment', label: 'Payment', x: 420, y: 220, service: 'Payment Processor' },
    { id: 'notification', label: 'Notify', x: 560, y: 150, service: 'Notification Service' },
    { id: 'postgres', label: 'PostgreSQL', x: 350, y: 300, service: 'PostgreSQL' },
    { id: 'redis', label: 'Redis', x: 200, y: 300, service: 'Redis' },
    { id: 'rabbitmq', label: 'RabbitMQ', x: 500, y: 300, service: 'RabbitMQ' },
  ]

  const edges = [
    { from: 'client', to: 'gateway' },
    { from: 'gateway', to: 'auth' },
    { from: 'gateway', to: 'account' },
    { from: 'gateway', to: 'transaction' },
    { from: 'transaction', to: 'fraud' },
    { from: 'transaction', to: 'payment' },
    { from: 'fraud', to: 'notification' },
    { from: 'account', to: 'postgres', dashed: true },
    { from: 'transaction', to: 'postgres', dashed: true },
    { from: 'auth', to: 'redis', dashed: true },
    { from: 'notification', to: 'rabbitmq', dashed: true },
  ]

  return (
    <div className="bg-slate-800 rounded-lg p-4 border border-slate-700 overflow-x-auto">
      <svg width="650" height="350" className="mx-auto">
        {/* Draw edges */}
        {edges.map((edge, i) => {
          const fromNode = nodes.find(n => n.id === edge.from)!
          const toNode = nodes.find(n => n.id === edge.to)!
          const fromStatus = fromNode.service ? getServiceStatus(fromNode.service) : 'healthy'
          const toStatus = toNode.service ? getServiceStatus(toNode.service) : 'healthy'
          const edgeStatus = fromStatus === 'down' || toStatus === 'down' ? 'down'
            : fromStatus === 'degraded' || toStatus === 'degraded' ? 'degraded'
            : 'healthy'

          return (
            <line
              key={i}
              x1={fromNode.x + 40}
              y1={fromNode.y}
              x2={toNode.x}
              y2={toNode.y}
              stroke={STATUS_COLORS[edgeStatus]}
              strokeWidth={2}
              strokeDasharray={edge.dashed ? '5,5' : undefined}
              className={!edge.dashed && edgeStatus === 'healthy' ? 'flow-animation' : undefined}
              opacity={edgeStatus === 'down' ? 0.3 : 0.7}
            />
          )
        })}

        {/* Draw nodes */}
        {nodes.map((node) => {
          const status = node.service ? getServiceStatus(node.service) : 'healthy'

          return (
            <g key={node.id}>
              <rect
                x={node.x - 10}
                y={node.y - 20}
                width={80}
                height={40}
                rx={6}
                fill="#1e293b"
                stroke={STATUS_COLORS[status]}
                strokeWidth={2}
              />
              <text
                x={node.x + 30}
                y={node.y + 5}
                textAnchor="middle"
                fill={STATUS_COLORS[status]}
                fontSize={12}
                fontWeight={500}
              >
                {node.label}
              </text>
            </g>
          )
        })}
      </svg>

      {/* Legend */}
      <div className="flex justify-center gap-6 mt-4 text-sm">
        <div className="flex items-center gap-2">
          <div className="w-3 h-3 rounded-full bg-green-500" />
          <span className="text-slate-400">Healthy</span>
        </div>
        <div className="flex items-center gap-2">
          <div className="w-3 h-3 rounded-full bg-yellow-500" />
          <span className="text-slate-400">Degraded</span>
        </div>
        <div className="flex items-center gap-2">
          <div className="w-3 h-3 rounded-full bg-red-500" />
          <span className="text-slate-400">Down</span>
        </div>
      </div>
    </div>
  )
}
