import os
import time
import random
import logging
import asyncio
from datetime import datetime
from typing import Optional
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST
from starlette.responses import Response

# =============================================================================
# Configuration
# =============================================================================
PORT = int(os.getenv("PORT", 3004))
SERVICE_NAME = os.getenv("SERVICE_NAME", "fraud-detection")

# Issue simulation flags
ENABLE_SLOW_SCORING = os.getenv("ENABLE_SLOW_SCORING", "false").lower() == "true"
SCORING_DELAY_MS = int(os.getenv("SCORING_DELAY_MS", 8000))

# =============================================================================
# Logging
# =============================================================================
logging.basicConfig(
    level=logging.INFO,
    format='{"timestamp": "%(asctime)s", "level": "%(levelname)s", "service": "' + SERVICE_NAME + '", "message": "%(message)s"}'
)
logger = logging.getLogger(__name__)

# =============================================================================
# Prometheus Metrics
# =============================================================================
fraud_scores = Histogram(
    "fraud_score_distribution",
    "Distribution of fraud scores",
    buckets=[0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
)

scoring_duration = Histogram(
    "fraud_scoring_duration_seconds",
    "Time to compute fraud score",
    buckets=[0.1, 0.5, 1, 2, 5, 10, 30]
)

scoring_requests = Counter(
    "fraud_scoring_requests_total",
    "Total scoring requests",
    ["decision"]
)

slow_scoring_active = Gauge(
    "slow_scoring_active",
    "Whether slow scoring simulation is active"
)
slow_scoring_active.set(1 if ENABLE_SLOW_SCORING else 0)

# =============================================================================
# FastAPI App
# =============================================================================
app = FastAPI(title="Fraud Detection Service", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# =============================================================================
# Models
# =============================================================================
class Transaction(BaseModel):
    transactionId: str
    fromAccountId: str
    toAccountId: str
    amount: float
    type: str = "transfer"

class ScoreResponse(BaseModel):
    transactionId: str
    score: float
    decision: str
    factors: list
    processingTime: str

# =============================================================================
# Fraud Scoring Logic (Mock ML Model)
# =============================================================================
def calculate_fraud_score(transaction: Transaction) -> tuple[float, list]:
    """
    Mock ML fraud scoring model.
    In production, this would call a real ML model.
    """
    factors = []
    base_score = 0.05  # Base fraud probability

    # Factor 1: Large amount (> $5000)
    if transaction.amount > 5000:
        base_score += 0.15
        factors.append({"factor": "large_amount", "impact": 0.15})

    # Factor 2: Very large amount (> $10000)
    if transaction.amount > 10000:
        base_score += 0.20
        factors.append({"factor": "very_large_amount", "impact": 0.20})

    # Factor 3: Round number (often suspicious)
    if transaction.amount % 1000 == 0:
        base_score += 0.05
        factors.append({"factor": "round_number", "impact": 0.05})

    # Factor 4: Random noise (simulates model uncertainty)
    noise = random.uniform(-0.05, 0.10)
    base_score += noise

    # Clamp to [0, 1]
    final_score = max(0.0, min(1.0, base_score))

    return final_score, factors

def make_decision(score: float) -> str:
    """
    Convert fraud score to decision.
    """
    if score < 0.3:
        return "approved"
    elif score < 0.7:
        return "flagged"
    else:
        return "rejected"

# =============================================================================
# Routes
# =============================================================================
@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "service": SERVICE_NAME,
        "timestamp": datetime.utcnow().isoformat(),
        "issues": {
            "slowScoringEnabled": ENABLE_SLOW_SCORING,
            "scoringDelayMs": SCORING_DELAY_MS
        }
    }

@app.get("/metrics")
async def metrics():
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)

@app.post("/score", response_model=ScoreResponse)
async def score_transaction(transaction: Transaction):
    start_time = time.time()

    logger.info(f"Scoring transaction {transaction.transactionId}, amount: ${transaction.amount}")

    # ISSUE SIMULATION: Slow scoring to cause cascade timeouts
    if ENABLE_SLOW_SCORING:
        delay_seconds = SCORING_DELAY_MS / 1000
        logger.warning(f"Slow scoring enabled, delaying {delay_seconds}s")
        await asyncio.sleep(delay_seconds)

    # Calculate fraud score
    score, factors = calculate_fraud_score(transaction)
    decision = make_decision(score)

    # Record metrics
    fraud_scores.observe(score)
    scoring_requests.labels(decision=decision).inc()

    processing_time = time.time() - start_time
    scoring_duration.observe(processing_time)

    logger.info(f"Transaction {transaction.transactionId} scored: {score:.4f} -> {decision} in {processing_time:.2f}s")

    return ScoreResponse(
        transactionId=transaction.transactionId,
        score=round(score, 4),
        decision=decision,
        factors=factors,
        processingTime=f"{processing_time:.2f}s"
    )

@app.post("/batch-score")
async def batch_score(transactions: list[Transaction]):
    """
    Score multiple transactions at once.
    """
    results = []
    for tx in transactions:
        score, factors = calculate_fraud_score(tx)
        decision = make_decision(score)
        results.append({
            "transactionId": tx.transactionId,
            "score": round(score, 4),
            "decision": decision
        })
        fraud_scores.observe(score)
        scoring_requests.labels(decision=decision).inc()

    return {"results": results}

@app.get("/model-info")
async def model_info():
    """
    Return information about the fraud model.
    """
    return {
        "modelVersion": "v1.0.0-demo",
        "lastTrainedAt": "2024-01-01T00:00:00Z",
        "features": [
            "transaction_amount",
            "round_number_check",
            "model_noise"
        ],
        "thresholds": {
            "approved": "< 0.3",
            "flagged": "0.3 - 0.7",
            "rejected": "> 0.7"
        }
    }

# =============================================================================
# Main
# =============================================================================
if __name__ == "__main__":
    import uvicorn

    logger.info(f"{SERVICE_NAME} starting on port {PORT}")

    if ENABLE_SLOW_SCORING:
        logger.warning(f"SLOW SCORING SIMULATION ENABLED: {SCORING_DELAY_MS}ms delay per request")

    uvicorn.run(app, host="0.0.0.0", port=PORT, log_level="info")
