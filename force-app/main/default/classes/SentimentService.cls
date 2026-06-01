/**
 * ═══════════════════════════════════════════════════════════════════════════
 * FILE 3: SentimentService.cls
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * PURPOSE: Handles sentiment capture and aggregation
 * 
 * TASKS COVERED:
 *   - US-041-BE-021: Build SentimentService.cls
 * 
 * FEATURES:
 *   - Create sentiment records on swipe
 *   - Aggregate sentiment scores for employers
 *   - Provide sentiment tag options for UI
 * ═══════════════════════════════════════════════════════════════════════════
 */
public with sharing class SentimentService {
    
    /** Predefined positive sentiment tags */
    public static final List<String> POSITIVE_SIGNALS = new List<String>{
        'Company culture',
        'Tech stack',
        'Growth opportunity',
        'Work environment',
        'Leadership team',
        'Mission/values alignment',
        'Work-life balance',
        'Compensation/benefits',
        'Remote flexibility',
        'Industry reputation'
    };
    
    /** Predefined negative sentiment tags */
    public static final List<String> NEGATIVE_SIGNALS = new List<String>{
        'Poor reviews',
        'Limited growth',
        'Industry mismatch',
        'Location/commute',
        'Company size',
        'Culture concerns',
        'Compensation concerns',
        'Work-life balance concerns',
        'Management concerns',
        'Job security concerns'
    };
    
    /**
     * Creates a sentiment record linked to a swipe event.
     * 
     * @param candidateId Contact Id
     * @param employerId Account Id
     * @param swipeEventId Swipe_Event__c Id
     * @param direction 'Right' or 'Left'
     * @param signals List of selected sentiment tags
     * @param freeText Optional free-form feedback
     * @return The created Employer_Sentiment__c record
     */
    public static Employer_Sentiment__c createSentiment(
        Id candidateId,
        Id employerId,
        Id swipeEventId,
        String direction,
        List<String> signals,
        String freeText
    ) {
        Employer_Sentiment__c sentiment = new Employer_Sentiment__c(
            Candidate__c = candidateId,
            Employers__c = employerId,
            Swipe_Event__c = swipeEventId,
            Free_Text_Feedback__c = freeText
        );
        
        // Store signals in appropriate field based on swipe direction
        String signalsString = signals != null && !signals.isEmpty() 
                              ? String.join(signals, ';') 
                              : null;
        
        if (direction == 'Right') {
            sentiment.Positive_Signals__c = signalsString;
        } else {
            sentiment.Negative_Signals__c = signalsString;
        }
        
        insert sentiment;
        
        // Trigger async aggregation for employer sentiment score
        if (!Test.isRunningTest()) {
            aggregateEmployerSentimentAsync(employerId);
        }
        
        return sentiment;
    }
    
    /**
     * Returns available sentiment tags for UI dropdown.
     */
    public static Map<String, List<String>> getSentimentTags() {
        return new Map<String, List<String>>{
            'positive' => POSITIVE_SIGNALS,
            'negative' => NEGATIVE_SIGNALS
        };
    }
    
    /**
     * Async wrapper for sentiment aggregation.
     * Runs in separate transaction to avoid blocking swipe flow.
     */
    @future
    public static void aggregateEmployerSentimentAsync(Id employerId) {
        aggregateEmployerSentiment(employerId);
    }
    
    /**
     * Aggregates all sentiment data for an employer.
     * Updates Account fields:
     *   - Overall_Sentiment_Score__c (0-100)
     *   - Positive_Signal_Summary__c (JSON)
     *   - Negative_Signal_Summary__c (JSON)
     *   - Sentiment_Data_Count__c
     *   - Sentiment_Trend__c
     */
    public static void aggregateEmployerSentiment(Id employerId) {
        // Count total sentiment records
        Integer sentimentCount = [
            SELECT COUNT() 
            FROM Employer_Sentiment__c 
            WHERE Employers__c = :employerId
        ];
        
        // Need minimum 10 records for meaningful score
        if (sentimentCount < 10) {
            Account employer = new Account(
                Id = employerId,
                Sentiment_Data_Count__c = sentimentCount,
                Sentiment_Trend__c = 'Insufficient Data'
            );
            update employer;
            return;
        }
        
        // Aggregate signal counts
        Map<String, Integer> positiveCount = new Map<String, Integer>();
        Map<String, Integer> negativeCount = new Map<String, Integer>();
        Integer totalPositive = 0;
        Integer totalNegative = 0;
        
        for (Employer_Sentiment__c sent : [
            SELECT Positive_Signals__c, Negative_Signals__c
            FROM Employer_Sentiment__c
            WHERE Employers__c = :employerId
        ]) {
            // Count positive signals
            if (String.isNotBlank(sent.Positive_Signals__c)) {
                totalPositive++;
                for (String signal : sent.Positive_Signals__c.split(';')) {
                    Integer cnt = positiveCount.get(signal);
                    positiveCount.put(signal, (cnt == null ? 0 : cnt) + 1);
                }
            }
            
            // Count negative signals
            if (String.isNotBlank(sent.Negative_Signals__c)) {
                totalNegative++;
                for (String signal : sent.Negative_Signals__c.split(';')) {
                    Integer cnt = negativeCount.get(signal);
                    negativeCount.put(signal, (cnt == null ? 0 : cnt) + 1);
                }
            }
        }
        
        // Calculate overall score (0-100)
        // Score = (positive / total) * 100
        Decimal score = 50; // Neutral baseline
        if (totalPositive + totalNegative > 0) {
            score = (Decimal.valueOf(totalPositive) / (totalPositive + totalNegative)) * 100;
        }
        
        // Update employer record
        Account employer = new Account(
            Id = employerId,
            Overall_Sentiment_Score__c = score.setScale(0),
            Positive_Signal_Summary__c = JSON.serialize(positiveCount),
            Negative_Signal_Summary__c = JSON.serialize(negativeCount),
            Sentiment_Data_Count__c = sentimentCount,
            Sentiment_Last_Updated__c = DateTime.now(),
            Sentiment_Trend__c = 'Stable' // Would need historical data for real trend
        );
        
        update employer;
    }
}