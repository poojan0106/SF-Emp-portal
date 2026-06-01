/**
 * SentimentAggregationBatch
 * Runs daily to aggregate sentiment scores for employers
 * Schedule: Daily at 2:00 AM
 */
global class SentimentAggregationBatch implements Database.Batchable<SObject>, Schedulable {
    
    global void execute(SchedulableContext sc) {
        Database.executeBatch(this, 50);
    }
    
    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Name
            FROM Account
            WHERE Is_Employer__c = true
        ]);
    }
    
    global void execute(Database.BatchableContext bc, List<Account> employers) {
        Set<Id> employerIds = new Set<Id>();
        for (Account emp : employers) {
            employerIds.add(emp.Id);
        }
        
        // Get all sentiment records
        Map<Id, List<Employer_Sentiment__c>> sentimentsByEmployer = 
            new Map<Id, List<Employer_Sentiment__c>>();
        
        for (Employer_Sentiment__c sentiment : [
            SELECT Employers__c, Sentiment_Type__c, 
                   Positive_Signals__c, Negative_Signals__c,
                   Free_Text_Feedback__c, Timestamp__c
            FROM Employer_Sentiment__c
            WHERE Employers__c IN :employerIds
            AND Timestamp__c >= LAST_N_DAYS:365
        ]) {
            if (!sentimentsByEmployer.containsKey(sentiment.Employers__c)) {
                sentimentsByEmployer.put(sentiment.Employers__c, 
                    new List<Employer_Sentiment__c>());
            }
            sentimentsByEmployer.get(sentiment.Employers__c).add(sentiment);
        }
        
        // Calculate scores and update accounts
        List<Account> accountsToUpdate = new List<Account>();
        
        for (Account emp : employers) {
            List<Employer_Sentiment__c> sentiments = 
                sentimentsByEmployer.get(emp.Id);
            
            if (sentiments == null || sentiments.size() < 10) {
                emp.Sentiment_Trend__c = 'Insufficient_Data';
            } else {
                SentimentCalculation calc = calculateSentiment(sentiments);
                emp.Overall_Sentiment_Score__c = calc.score;
                emp.Sentiment_Trend__c = calc.trend;
            }
            
            emp.Sentiment_Last_Updated__c = DateTime.now();
            accountsToUpdate.add(emp);
        }
        
        update accountsToUpdate;
    }
    
    global void finish(Database.BatchableContext bc) {
        // Log completion
        System.debug('Sentiment aggregation batch completed');
    }
    
    private SentimentCalculation calculateSentiment(
        List<Employer_Sentiment__c> sentiments
    ) {
        Integer positiveCount = 0;
        Integer negativeCount = 0;
        
        for (Employer_Sentiment__c s : sentiments) {
            if (s.Sentiment_Type__c == 'Positive') {
                positiveCount++;
            } else {
                negativeCount++;
            }
        }
        
        Integer total = positiveCount + negativeCount;
        Decimal score = (Decimal.valueOf(positiveCount) / total) * 100;
        
        // Calculate trend (compare last 30 days to previous 30)
        // Simplified - would need more logic in production
        String trend = 'Stable';
        
        return new SentimentCalculation(score.intValue(), trend);
    }
    
    public class SentimentCalculation {
        public Integer score;
        public String trend;
        
        public SentimentCalculation(Integer s, String t) {
            this.score = s;
            this.trend = t;
        }
    }
}

// Schedule: System.schedule('Sentiment Aggregation', '0 0 2 * * ?', new SentimentAggregationBatch());