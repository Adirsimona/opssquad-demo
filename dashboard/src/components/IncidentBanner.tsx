import { AlertCircle } from 'lucide-react'

interface IncidentBannerProps {
  message: string
}

export function IncidentBanner({ message }: IncidentBannerProps) {
  const isCritical = message.toLowerCase().includes('critical')

  return (
    <div className={`mb-6 p-4 rounded-lg border ${
      isCritical
        ? 'bg-red-900/50 border-red-700'
        : 'bg-yellow-900/50 border-yellow-700'
    }`}>
      <div className="flex items-center gap-3">
        <AlertCircle className={`w-6 h-6 ${isCritical ? 'text-red-400' : 'text-yellow-400'}`} />
        <div>
          <div className={`font-semibold ${isCritical ? 'text-red-300' : 'text-yellow-300'}`}>
            Active Incident
          </div>
          <div className={isCritical ? 'text-red-200' : 'text-yellow-200'}>
            {message}
          </div>
        </div>
      </div>
    </div>
  )
}
