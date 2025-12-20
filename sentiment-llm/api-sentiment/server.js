import './telemetry.js'

import express from 'express'
import fs from 'node:fs/promises'
import { createReadStream } from 'node:fs'
import path from 'node:path'
import readline from 'node:readline'

import { SpanStatusCode, metrics, trace } from '@opentelemetry/api'
import apiLogs from '@opentelemetry/api-logs'

const app = express()
app.use(express.json({ limit: '1mb' }))

const { logs } = apiLogs

const tracer = trace.getTracer('sentiment-api')
const meter = metrics.getMeter('sentiment-api')
const ollamaLatencyMs = meter.createHistogram('ollama_inference_latency_ms', {
  unit: 'ms',
})
const sentimentWrites = meter.createCounter('sentiment_comments_created_total')
const otelLogger = logs.getLogger('sentiment-api')

const port = Number.parseInt(process.env.PORT || '8080', 10)
const dataDir = process.env.DATA_DIR || '/data'
const csvPath = process.env.CSV_PATH || path.join(dataDir, 'comments.csv')

const ollamaBaseUrl = process.env.OLLAMA_BASE_URL || 'http://ollama:11434'
const ollamaModel = process.env.OLLAMA_MODEL || 'qwen2.5:0.5b'
const ollamaPullOnDemand = (process.env.OLLAMA_PULL_ON_DEMAND || 'true').toLowerCase() === 'true'

let modelEnsured = false

function csvEscape(value) {
  const s = String(value ?? '')
  const escaped = s.replaceAll('"', '""')
  return `"${escaped}"`
}

function csvParseLine(line) {
  // Minimal CSV parser for: timestamp,text,label,confidence,latency_ms
  const out = []
  let cur = ''
  let inQuotes = false
  for (let i = 0; i < line.length; i++) {
    const ch = line[i]
    if (inQuotes) {
      if (ch === '"') {
        const next = line[i + 1]
        if (next === '"') {
          cur += '"'
          i++
        } else {
          inQuotes = false
        }
      } else {
        cur += ch
      }
      continue
    }

    if (ch === '"') {
      inQuotes = true
      continue
    }

    if (ch === ',') {
      out.push(cur)
      cur = ''
      continue
    }

    cur += ch
  }
  out.push(cur)
  return out
}

async function ensureCsv() {
  await fs.mkdir(dataDir, { recursive: true })
  try {
    await fs.access(csvPath)
  } catch {
    await fs.writeFile(csvPath, 'timestamp,text,label,confidence,latency_ms\n', 'utf8')
  }
}

async function appendRecord(record) {
  const line = [
    csvEscape(record.timestamp),
    csvEscape(record.text),
    csvEscape(record.label),
    csvEscape(record.confidence),
    csvEscape(record.latency_ms),
  ].join(',')
  await fs.appendFile(csvPath, `${line}\n`, 'utf8')
}

async function readLastRecords(limit) {
  await ensureCsv()

  const records = []
  const rl = readline.createInterface({
    input: createReadStream(csvPath, { encoding: 'utf8' }),
    crlfDelay: Number.POSITIVE_INFINITY,
  })

  let isHeader = true
  for await (const line of rl) {
    if (isHeader) {
      isHeader = false
      continue
    }
    if (!line.trim()) continue
    const [timestamp, text, label, confidence, latencyMs] = csvParseLine(line)
    records.push({
      timestamp,
      text,
      label,
      confidence: Number.parseFloat(confidence),
      latency_ms: Number.parseInt(latencyMs, 10),
    })
  }

  // Return newest first.
  records.sort((a, b) => (a.timestamp < b.timestamp ? 1 : -1))
  return records.slice(0, limit)
}

function normalizeLabel(label) {
  const s = String(label || '').toLowerCase().trim()
  if (s.includes('positive')) return 'positive'
  if (s.includes('negative')) return 'negative'
  return 'neutral'
}

async function analyzeWithOllama(text) {
  return tracer.startActiveSpan(
    'ollama.chat',
    {
      attributes: {
        'ollama.model': ollamaModel,
      },
    },
    async (span) => {
      const start = Date.now()
      try {
        if (!modelEnsured && ollamaPullOnDemand) {
          // Ensure the model exists (best effort). This avoids first-request failures when the
          // Ollama container is up but the model isn't pulled yet.
          try {
            const show = await fetch(`${ollamaBaseUrl}/api/show`, {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ name: ollamaModel }),
            })

            if (!show.ok) {
              await fetch(`${ollamaBaseUrl}/api/pull`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ name: ollamaModel, stream: false }),
              }).catch(() => null)
            }
          } catch {
            // If Ollama isn't reachable yet, the main request will throw anyway.
          }

          modelEnsured = true
        }

        const body = {
          model: ollamaModel,
          stream: false,
          format: 'json',
          messages: [
            {
              role: 'system',
              content:
                'You are a strict sentiment classifier. Return ONLY valid JSON with shape: {"label":"positive|negative|neutral","confidence":number between 0 and 1}.',
            },
            {
              role: 'user',
              content: text,
            },
          ],
          options: {
            temperature: 0,
          },
        }

        const res = await fetch(`${ollamaBaseUrl}/api/chat`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(body),
        })

        const latencyMs = Date.now() - start
        span.setAttribute('ollama.latency_ms', latencyMs)

        if (!res.ok) {
          const msg = await res.text().catch(() => '')
          throw new Error(`ollama HTTP ${res.status}: ${msg}`)
        }

        const data = await res.json()
        const content = data?.message?.content
        const raw = typeof content === 'string' ? content : ''
        let parsed = null
        try {
          parsed = typeof content === 'string' ? JSON.parse(content) : null
        } catch {
          parsed = null
        }

        const label = normalizeLabel(parsed?.label ?? raw)
        let confidence = 0.5
        if (typeof parsed?.confidence === 'number') {
          confidence = parsed.confidence
        } else {
          const match = raw.match(/"confidence"\s*:\s*([0-9]*\.?[0-9]+)/)
          if (match) confidence = Number.parseFloat(match[1])
        }
        confidence = Math.max(0, Math.min(1, confidence))

        ollamaLatencyMs.record(latencyMs, {
          'ollama.model': ollamaModel,
          'sentiment.label': label,
        })

        span.setAttribute('sentiment.label', label)
        span.setAttribute('sentiment.confidence', confidence)

        otelLogger.emit({
          severityText: 'INFO',
          body: 'ollama sentiment inference complete',
          attributes: {
            'ollama.model': ollamaModel,
            'sentiment.label': label,
          },
        })

        return { label, confidence, latency_ms: latencyMs }
      } catch (e) {
        span.recordException(e)
        span.setStatus({
          code: SpanStatusCode.ERROR,
          message: e?.message || 'ollama_error',
        })
        throw e
      } finally {
        span.end()
      }
    },
  )
}

app.get('/api/v1/health', async (_req, res) => {
  try {
    await ensureCsv()
    res.json({ status: 'ok' })
  } catch (e) {
    res.status(500).json({ status: 'error', error: e?.message || String(e) })
  }
})

app.get('/api/v1/comments', async (req, res) => {
  const limit = Math.max(1, Math.min(200, Number.parseInt(req.query.limit || '25', 10)))
  const items = await readLastRecords(limit)
  res.json({ items })
})

app.post('/api/v1/comments', async (req, res) => {
  try {
    const text = req.body?.text
    if (typeof text !== 'string' || !text.trim()) {
      res.status(400).json({ error: 'text is required' })
      return
    }

    await ensureCsv()
    const timestamp = new Date().toISOString()
    const { label, confidence, latency_ms } = await analyzeWithOllama(text)

    const record = {
      timestamp,
      text,
      label,
      confidence,
      latency_ms,
    }

    await appendRecord(record)
    sentimentWrites.add(1, {
      'sentiment.label': record.label,
    })
    res.json(record)
  } catch (e) {
    res.status(500).json({ error: e?.message || String(e) })
  }
})

await ensureCsv()
app.listen(port, () => {
  // eslint-disable-next-line no-console
  console.log(`sentiment-api listening on :${port}`)
})
