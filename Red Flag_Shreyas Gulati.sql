-- RedFlag — Fraud Detection Submission
-- Student:Shreyas Gulati | Batch: DA-1
USE redflag;
-- Pattern 1 Velocity Fraud
/*The pattern: A legitimate user makes 3-8 transactions per day on their busiest days. A fraudster running
an automated script can make 30+ in a single day. Anyone hitting that count is either a bot, an account
takeover, or a merchant running a churning scheme.
The signature: A single user_id with 30 or more distinct transactions on any one calendar date.*/
SELECT user_id, DATE(txn_time) AS transaction_date, COUNT(DISTINCT txn_id) AS transaction_count
FROM transactions
GROUP BY user_id, DATE(txn_time)
HAVING COUNT(DISTINCT txn_id) >= 30
ORDER BY transaction_count DESC, transaction_date;
-- Pattern 2 Round-Amount clustering
/*The pattern: Money launderers prefer round-number amounts (₹100, ₹500, ₹1,000, ₹5,000, ₹10,000).
Real e-commerce and food-delivery transactions rarely produce clean round numbers because prices
include taxes, delivery fees, and discounts. A user with 15+ exactly-round transactions is showing
money-laundering signature.
The signature: A single user_id with 15+ transactions where amount is exactly one of: 100, 200, 500,
1000, 2000, 5000, 10000.*/
SELECT user_id, COUNT(*) AS round_numbers_transactions
FROM transactions
WHERE amount IN (100, 200, 500, 1000, 2000, 5000, 10000)
GROUP BY user_id
HAVING COUNT(*) >= 15
ORDER BY round_numbers_transactions DESC;
-- Pattern3 Card Testing
/*The pattern: Fraudsters buy dumps of stolen credit card numbers on the dark web. They test which
cards are still active by attempting tiny purchases (under ₹10). If the purchase goes through, the card is
still valid and the fraudster keeps it for a bigger operation. If it fails, they move to the next card. This is
one of the most common frauds detected by real card networks.
The signature: A single user_id with 30+ transactions under ₹10 in a single day.*/
SELECT user_id, DATE(txn_time) AS transaction_date, COUNT(*) AS small_transactions
FROM transactions
WHERE amount < 10
GROUP BY user_id, DATE(txn_time)
HAVING COUNT(*) >= 30
ORDER BY small_transactions DESC;
-- Pattern 4 Failed-then-Succeeded(Basic Version)
/*The pattern: Same card-testing behaviour as P3, but the specific signature this time is many FAILED
transactions followed by SUCCESS ones. Fraudsters retry until they find a card/CVV combination that
clears. Real users rarely have more than 2-3 failed transactions in an entire year. Users with 20+ failures
are running scripts.
The signature (simplified): A single user_id with 20+ transactions where status = 'FAILED'.*/
SELECT user_id, COUNT(*) AS unsuccessful_transactions
FROM transactions
WHERE status = 'FAILED'
GROUP BY user_id
HAVING COUNT(*) >= 20
ORDER BY unsuccessful_transactions DESC;
-- Advanced Version
/*The signature (advanced): A user_id with 20+ pairs where a FAILED transaction is followed
within 2 minutes by a SUCCESS transaction of the same amount.*/
SELECT t1.user_id, COUNT(*) AS fail_success_pairs
FROM transactions t1
JOIN transactions t2
ON t1.user_id = t2.user_id
AND t1.amount = t2.amount
AND t1.status = 'FAILED'
AND t2.status = 'SUCCESS'
AND t2.txn_time > t1.txn_time
AND TIMESTAMPDIFF(MINUTE, t1.txn_time, t2.txn_time) <= 2
GROUP BY t1.user_id
HAVING COUNT(*) >= 20
ORDER BY fail_success_pairs DESC;
-- Pattern 5 Odd-Hour Concentration
/*The pattern: Real Indian users transact between 8 AM and 11 PM. Automated fraud scripts often run in
the 2 AM - 5 AM window (which is business hours in North American timezones - many card-cracking
rings operate from Eastern Europe and the Americas). A user with the vast majority of their activity in
this window is exhibiting bot signature.
The signature: A user_id where 80% or more of their transactions occur between 2 AM and 5 AM (hours
2, 3, 4), and they have at least 30 total transactions.*/
SELECT user_id, COUNT(*) AS total_transactions,
SUM(CASE
WHEN HOUR(txn_time) BETWEEN 2 AND 4 THEN 1
ELSE 0
END) AS odd_hour_transactions,
ROUND(SUM(CASE 
WHEN HOUR(txn_time) BETWEEN 2 AND 4 THEN 1
ELSE 0 
END)/ COUNT(*),2) AS transaction_ratio
FROM transactions
GROUP BY user_id
HAVING COUNT(*) >= 30 AND -- COUNT Function counts every row in each group formed by user id.So it gives total tranactions. 
SUM(CASE 
WHEN HOUR(txn_time) BETWEEN 2 AND 4 THEN 1 
ELSE 0 
END) / COUNT(*) >= 0.80
ORDER BY transaction_ratio DESC;
-- Pattern 6 Mule Accounts (Basic Version)
/*The pattern: Mule accounts are the human ATMs of the fraud world. A fraudster deposits stolen funds
into a mule's account, then quickly withdraws or transfers them elsewhere. The mule keeps a small
commission. Behaviour signature: large CREDIT transactions (money coming in via NETBANKING)
immediately followed by DEBIT transactions (money going out via UPI) within 30 minutes.
The signature (simplified): A user with 8 or more CREDIT transactions. Not perfect, but flags
most mules.*/
SELECT user_id, COUNT(*) AS credit_transactions
FROM transactions
WHERE txn_type = 'CREDIT'
GROUP BY user_id
HAVING COUNT(*) >= 8
ORDER BY credit_transactions DESC;
-- (Advanced Version)
/*The signature (advanced, Week 4): A user with 5+ instances where a CREDIT is followed within 30
minutes by a DEBIT of at least 70% of the credit amount.*/
SELECT t1.user_id, COUNT(*) AS mule_transactions
FROM transactions t1
WHERE t1.txn_type = 'CREDIT'
AND EXISTS (SELECT user_id
FROM transactions t2
WHERE t2.user_id = t1.user_id
AND t2.txn_type = 'DEBIT'
AND t2.txn_time > t1.txn_time
AND TIMESTAMPDIFF(MINUTE, t1.txn_time, t2.txn_time) <= 30
AND t2.amount >= 0.70 * t1.amount)
GROUP BY t1.user_id
HAVING COUNT(*) >= 5
ORDER BY mule_transactions DESC;
-- Pattern 7 Refund Abuse
/*The pattern: Real users have refund rates below 5%. Fraudsters running chargeback schemes or
exploiting merchant loopholes have refund rates above 40%. The signature is a user with many
transactions where a disproportionate share are refunds.
The signature: A user with 20+ total transactions AND a refund ratio (REFUNDS / TOTAL) greater than
40%.*/
SELECT user_id, COUNT(*) AS total_transactions,
SUM(CASE
WHEN txn_type = 'REFUND' THEN 1
ELSE 0
END) AS refund_transactions,
ROUND(SUM(CASE 
WHEN txn_type = 'REFUND' THEN 1 
ELSE 0 
END) / COUNT(*),2) AS refund_ratio
FROM transactions
GROUP BY user_id
HAVING COUNT(*) >= 20 AND
SUM(CASE 
WHEN txn_type = 'REFUND' THEN 1 
ELSE 0 
END) / COUNT(*) > 0.40
ORDER BY refund_ratio DESC;
-- Pattern 8 Merchant Collusion
/*The pattern: Legitimate merchants have long tails of customers - thousands of users each contributing
small amounts to the merchant's total volume. A merchant where 3-4 users generate the majority of
volume is either a very niche B2B business (rare on retail platforms) or is colluding with those users to
launder money.
The signature: A merchant where the top 5 users by volume account for more than 60% of the
merchant's total transaction value.*/
WITH user_contribution AS (
SELECT merchant_id, user_id,SUM(amount) AS user_total
FROM transactions
GROUP BY merchant_id, user_id),
ranked_users AS (
SELECT merchant_id, user_id, user_total, 
ROW_NUMBER() OVER 
(PARTITION BY merchant_id
ORDER BY user_total DESC) AS rn
FROM user_contribution),
merchant_total AS (
SELECT merchant_id, SUM(amount) AS total_amount
FROM transactions
GROUP BY merchant_id)
SELECT mt.merchant_id, mt.total_amount, SUM(ru.user_total) AS top5_amount, ROUND(SUM(ru.user_total) / mt.total_amount, 2) AS concentration_ratio
FROM merchant_total mt
JOIN ranked_users ru
ON mt.merchant_id= ru.merchant_id
WHERE ru.rn <= 5
GROUP BY mt.merchant_id, mt.total_amount
HAVING SUM(ru.user_total) / mt.total_amount > 0.60
ORDER BY concentration_ratio DESC;
-- Pattern 9 Just-Under-Threshhold
/*The pattern: Indian banking regulations require enhanced KYC checks on transactions of ₹10,000 or
above. Fraudsters running structuring / smurfing schemes deliberately keep transactions at exactly
₹9,999 to avoid these checks. This is one of the most classic anti-money-laundering patterns and is
illegal even without any other fraud.
The signature: A user with 10 or more transactions at exactly ₹9,999.00.*/
SELECT user_id, COUNT(*) AS suspicious_transactions
FROM transactions
WHERE amount = 9999.00
GROUP BY user_id
HAVING COUNT(*) >= 10
ORDER BY suspicious_transactions DESC;
-- Pattern 10 Dormant-then-Active
/*The pattern: An account that was completely inactive for 90+ days and then suddenly bursts with 15+
transactions in a short window is the signature of account takeover. The fraudster has gained access to a
dormant account (via a phishing attack, credential leak, or SIM swap) and is monetising it before the real
owner notices.
The signature: A user who has a gap of 90+ days between two consecutive transactions, followed by 15+
transactions after the gap.*/
WITH txn_gaps AS (
SELECT user_id, txn_time,
LAG(txn_time) 
OVER 
(PARTITION BY user_id
ORDER BY txn_time) AS previous_txn
FROM transactions),
restart_transactions AS (
SELECT user_id, txn_time AS restart_time
FROM txn_gaps
WHERE previous_txn IS NOT NULL
AND DATEDIFF(txn_time, previous_txn) >= 90)
SELECT r.user_id,COUNT(t.txn_time) AS post_restart_transactions
FROM restart_transactions r
JOIN transactions t
ON r.user_id = t.user_id
AND t.txn_time >= r.restart_time
GROUP BY r.user_id
HAVING COUNT(t.txn_time) >= 15
ORDER BY post_restart_transactions DESC;
-- Pattern 11 Velocity Spike
/*The pattern: A user's transaction rate suddenly spikes to many multiples of their historical average. This
is the ML-free equivalent of anomaly detection - even without training a model, you can identify
accounts whose behaviour changed abruptly. Almost always indicates account takeover.
The signature: A user whose peak monthly transaction count is at least 5x their average monthly
transaction count (and peak is at least 20 transactions).*/
WITH monthly_txns AS (
SELECT user_id, YEAR(txn_time) AS yr, MONTH(txn_time) AS mn, COUNT(*) AS monthly_count
FROM transactions
GROUP BY user_id, YEAR(txn_time), MONTH(txn_time)),
user_stats AS (
SELECT user_id, SUM(monthly_count)/6.0 AS avg_monthly_txns, MAX(monthly_count) AS peak_monthly_txns
FROM monthly_txns
GROUP BY user_id)
SELECT user_id, avg_monthly_txns, peak_monthly_txns, ROUND(peak_monthly_txns / avg_monthly_txns, 2) AS spike_ratio
FROM user_stats
WHERE peak_monthly_txns >= 20
AND peak_monthly_txns / avg_monthly_txns >= 5
ORDER BY spike_ratio DESC;
-- Pattern 12 Geographic Impossibility
/*The pattern: The same user transacts in two different Indian cities within 60 minutes. Physically
impossible unless the account is being used simultaneously by two different people. Almost always
indicates account takeover or stolen-card usage across a syndicate.
The signature: A user_id where at least one pair of consecutive transactions occurs in different cities
within 60 minutes of each other.*/
WITH location_history AS (
SELECT user_id, city, txn_time,
LAG(city)
OVER 
(PARTITION BY user_id
ORDER BY txn_time) AS prev_city,
LAG(txn_time) 
OVER 
(PARTITION BY user_id
ORDER BY txn_time) AS prev_time
FROM transactions)
SELECT DISTINCT user_id
FROM location_history
WHERE prev_city IS NOT NULL
AND city!= prev_city
AND TIMESTAMPDIFF(MINUTE, prev_time, txn_time) <= 60;



