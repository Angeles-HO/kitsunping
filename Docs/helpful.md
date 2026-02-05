## Composite Score

SCORE = α·(RSRP_score) + β·(SINR_score) + γ·(Performance_score) − δ·(Jitter_penalty)

- α, β, γ, δ are weights (α + β + γ = 1; δ is the penalty term)
- Typical weights: α=0.4, β=0.3, γ=0.3, δ=0.1

## Sigmoid RSRP Mapping (better discrimination)

# Alternative more aggressive (midpoint at -100 dBm)

score_rsrp_aggressive() {
local rsrp=$1
	echo "100 / (1 + e(-0.15 * ($rsrp + 100)))" | bc -l
}

# Current version (midpoint at -105 dBm)

score_rsrp() {
local rsrp=$1
	echo "100 / (1 + e(-0.1 * ($rsrp + 105)))" | bc -l
}

# Alternative more tolerant (midpoint at -110 dBm)

score_rsrp_tolerant() {
local rsrp=$1
	echo "100 / (1 + e(-0.08 * ($rsrp + 110)))" | bc -l
}

## Optimization for Performance

# Avoid repeated calls to bc with lookup table caching

declare -A RSRP_CACHE

# Cached version of score_rsrp
# Usage: score_rsrp_cached <rsrp_value>
# Returns: score
# e. g. score_rsrp_cached -90 -> 88.1 
score_rsrp_cached() {
	local rsrp=$1 # Input RSRP value

	# Check cache
	[[ -n "${RSRP_CACHE[$rsrp]}" ]] && echo "${RSRP_CACHE[$rsrp]}" && return

	# Compute score and store in cache
	local score=$(echo "100 / (1 + e(-0.1 * ($rsrp + 105)))" | bc -l)

	# Store in cache
	RSRP_CACHE[$rsrp]=$score

	# Return score
	echo "$score"
}

# About of usage of cached, we need to have in mind that the RSRP values are usually
# in a limited range (e.g., -140 dBm to -40 dBm), so the cache will not grow indefinitely.
# Also about the time of computation, the cached version will be significantly faster
# after the first computation for each unique RSRP value.
# So if daemon sleep time is low and RSRP values vary a lot, the cache will be more beneficial.
# and Daemon cicles are faster.


## SINR (Signal-to-Interference-plus-Noise Ratio) to score mapping

# Sigmoid mapping for SINR (midpoint at 10 dB)
# Usage: score_sinr <sinr_value>
# Returns: score in the range 0-100
# Example: score_sinr 15 -> ~73.1
score_sinr() {
	local sinr=$1

	# Midpoint: 10 dB, slope: 0.2 for a smooth transition.
	# Use bc -l's exponential function e(x) (not the caret '^').
	echo "100 / (1 + e(-0.2 * ($sinr - 10)))" | bc -l
}

# Recommended interpretation (clear, non-overlapping ranges):
- Very poor: SINR <= -10 dB -> ~1.8%
- Poor:     -10 dB < SINR <= -5 dB -> ~4.7%
- Acceptable:-5 dB  < SINR <= 0 dB  -> ~11.9%
- Moderate: 0 dB   < SINR <= 5 dB  -> ~26.9%
- Medium:   5 dB   < SINR <= 10 dB -> ~50.0% (midpoint)
- Good:     10 dB  < SINR <= 15 dB -> ~73.1%
- Very good:15 dB  < SINR <= 20 dB -> ~88.1%
- Excellent:20 dB  < SINR <= 25 dB -> ~95.0%
- Outstanding:SINR > 25 dB -> ~98.2%



### Example RSRP -> score

- -70 dBm → 99.7%
- -90 dBm → 88.1%
- -110 dBm → 26.9%
- -130 dBm → 0.2%

# Considerations

 - The sigmoid mapping provides a smooth transition between scores, avoiding abrupt changes.
 - Handle small negative or fractional values consistently (units in dB). The sigmoid is continuous
	 around 0 dB; treat inputs as numeric (e.g., -0.25 dB is valid) and ensure the calling code passes
	 correctly-formatted numeric values to avoid bc errors.
