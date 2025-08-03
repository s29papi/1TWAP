'use client'

import { useState, useEffect } from 'react'
import { PlayIcon, PauseIcon, CheckCircleIcon, XCircleIcon, ClockIcon } from '@heroicons/react/24/outline'
import { Card, CardContent, CardHeader, CardTitle } from '@/src/components/ui/card'
import { Button } from '@/src/components/ui/button'
import { Progress } from '@/src/components/ui/progress'

export default function ExecutionMonitor() {
  const [isMonitoring, setIsMonitoring] = useState(true)
  const [canExecute, setCanExecute] = useState(true)
  const [executedChunks, setExecutedChunks] = useState(2)
  const [totalChunks] = useState(4)
  const [lastExecution, setLastExecution] = useState(Date.now() - 300000)

  useEffect(() => {
    if (!isMonitoring) return

    const interval = setInterval(() => {
      // Simulate execution logic
      const shouldExecute = Math.random() > 0.7
      setCanExecute(shouldExecute)
      
      if (shouldExecute && executedChunks < totalChunks) {
        setExecutedChunks(prev => Math.min(prev + 1, totalChunks))
        setLastExecution(Date.now())
      }
    }, 10000)

    return () => clearInterval(interval)
  }, [isMonitoring, executedChunks, totalChunks])

  const progress = (executedChunks / totalChunks) * 100

  const formatLastExecution = () => {
    const diff = Date.now() - lastExecution
    const minutes = Math.floor(diff / 60000)
    if (minutes < 1) return 'Just now'
    if (minutes === 1) return '1 minute ago'
    return `${minutes} minutes ago`
  }

  return (
    <Card className="bg-gray-900 border-gray-800">
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle className="text-white">Execution Monitor</CardTitle>
        <div className="flex items-center space-x-2">
          {isMonitoring && (
            <div className="flex items-center space-x-2">
              <div className="w-2 h-2 bg-green-500 rounded-full animate-pulse"></div>
              <span className="text-sm text-green-400">Live</span>
            </div>
          )}
          <Button
            variant="outline"
            size="sm"
            onClick={() => setIsMonitoring(!isMonitoring)}
            className="border-gray-700 text-gray-300 hover:bg-gray-800"
          >
            {isMonitoring ? (
              <PauseIcon className="h-4 w-4" />
            ) : (
              <PlayIcon className="h-4 w-4" />
            )}
          </Button>
        </div>
      </CardHeader>
      <CardContent className="space-y-4">
        {/* Progress Bar */}
        <div className="space-y-2">
          <div className="flex justify-between text-sm">
            <span className="text-gray-400">Progress</span>
            <span className="text-white">{executedChunks}/{totalChunks} chunks</span>
          </div>
          <Progress value={progress} className="h-2" />
        </div>

        {/* Status Cards */}
        <div className="grid grid-cols-1 gap-3">
          <div className="bg-gray-800 rounded-lg p-3 flex items-center justify-between">
            <div className="flex items-center space-x-3">
              {canExecute ? (
                <CheckCircleIcon className="h-5 w-5 text-green-400" />
              ) : (
                <XCircleIcon className="h-5 w-5 text-red-400" />
              )}
              <span className="text-sm text-gray-300">Can Execute</span>
            </div>
            <span className={`text-sm font-medium ${canExecute ? 'text-green-400' : 'text-red-400'}`}>
              {canExecute ? 'Yes' : 'No'}
            </span>
          </div>

          <div className="bg-gray-800 rounded-lg p-3 flex items-center justify-between">
            <div className="flex items-center space-x-3">
              <ClockIcon className="h-5 w-5 text-blue-400" />
              <span className="text-sm text-gray-300">Last Execution</span>
            </div>
            <span className="text-sm text-blue-400">{formatLastExecution()}</span>
          </div>

          <div className="bg-gray-800 rounded-lg p-3 flex items-center justify-between">
            <div className="flex items-center space-x-3">
              <div className="w-5 h-5 bg-purple-500 rounded flex items-center justify-center">
                <span className="text-xs font-bold text-white">{executedChunks}</span>
              </div>
              <span className="text-sm text-gray-300">Chunks Completed</span>
            </div>
            <span className="text-sm text-purple-400">{executedChunks}/{totalChunks}</span>
          </div>
        </div>

        {/* Status Message */}
        <div className="bg-gray-800 border-l-4 border-pink-500 p-3">
          <p className="text-sm text-gray-300">
            {canExecute 
              ? 'Volatility within threshold. Ready to execute next chunk.'
              : 'High volatility detected. Execution paused until conditions improve.'
            }
          </p>
        </div>
      </CardContent>
    </Card>
  )
}