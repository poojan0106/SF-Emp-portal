/**
 * EmployerDashboardController
 * REST API endpoint for employer dashboard
 * Endpoint: /services/apexrest/dashboard/*
 * 
 * Routes:
 * GET /services/apexrest/dashboard/metrics?accountId=001xx000xxx
 * GET /services/apexrest/dashboard/activity?accountId=001xx000xxx&limit=10
 * GET /services/apexrest/dashboard/recommendations?accountId=001xx000xxx
 * GET /services/apexrest/dashboard/events?accountId=001xx000xxx&limit=10
 */
@RestResource(urlMapping='/dashboard/*')
global without sharing class EmployerDashboardController {
    
    /**
     * Single GET handler that routes to different operations
     */
    @HttpGet
    global static void handleGet() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        
        System.debug('=== Dashboard API called ===');
        System.debug('Request URI: ' + req.requestURI);
        System.debug('Query Params: ' + req.params);
        
        try {
            // Parse the URL path to determine which operation
            String path = req.requestURI.substringAfter('/dashboard/');
            String operation = path.split('\\?')[0]; // Remove query params
            
            String accountId = req.params.get('accountId');
            System.debug('Account ID received: ' + accountId);
            
            if (String.isBlank(accountId)) {
                System.debug('ERROR: Account ID missing');
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(
                    new ErrorResponse(false, 'Account ID is required')
                ));
                return;
            }
            
            // Route to appropriate method
            if (operation.equals('metrics')) {
                getMetrics(accountId, res);
            } else if (operation.equals('activity')) {
                getActivity(accountId, res);
            } else if (operation.equals('recommendations')) {
                getRecommendations(accountId, res);
            } else if (operation.equals('events')) {
                getEvents(accountId, res);
            } else {
                res.statusCode = 404;
                res.responseBody = Blob.valueOf(JSON.serialize(
                    new ErrorResponse(false, 'Endpoint not found')
                ));
            }
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Dashboard error: ' + e.getMessage());
            RestContext.response.statusCode = 500;
            RestContext.response.responseBody = Blob.valueOf(JSON.serialize(
                new ErrorResponse(false, 'An error occurred: ' + e.getMessage())
            ));
        }
    }
    
    // ==================== ROUTE HANDLERS ====================
    
    private static void getMetrics(String accountId, RestResponse res) {
        try {
            System.debug('--- getMetrics START ---');
	        System.debug('AccountId: ' + accountId);
            
            DashboardData data = new DashboardData();
            
            // Get metrics
            data.activeJobs = [SELECT COUNT() FROM Campaign 
                WHERE Employer__c = :accountId 
                AND RecordType.DeveloperName = 'Talent_Pool' 
                AND IsActive = true];
            
            System.debug('Active Jobs: ' + data.activeJobs);
            
            data.talentPoolSize = [SELECT COUNT() FROM CampaignMember 
                WHERE Campaign.Employer__c = :accountId 
                AND Campaign.RecordType.DeveloperName = 'Talent_Pool'
                AND Status = 'Interested'];
            
            System.debug('Talent Pool Size: ' + data.talentPoolSize);
            
            Date weekAgo = Date.today().addDays(-7);
            System.debug('Week Ago Date: ' + weekAgo);
            
            data.newCandidatesThisWeek = [SELECT COUNT() FROM CampaignMember 
                WHERE Campaign.Employer__c = :accountId 
                AND Campaign.RecordType.DeveloperName = 'Talent_Pool'
                AND Interest_Date__c >= :weekAgo];
            
            System.debug('New Candidates This Week: ' + data.newCandidatesThisWeek);
            
            data.pendingInterviews = [SELECT COUNT() FROM CampaignMember 
                WHERE Campaign.Employer__c = :accountId 
                AND Status = 'Interview_Requested'];
            
            System.debug('Pending Interviews: ' + data.pendingInterviews);
            
            data.pendingOffers = [SELECT COUNT() FROM CampaignMember 
                WHERE Campaign.Employer__c = :accountId 
                AND Status = 'Offered'];
            System.debug('Pending Offers: ' + data.pendingOffers);
            
            data.readyForInterview = [SELECT COUNT() FROM CampaignMember 
                WHERE Campaign.Employer__c = :accountId 
                AND AI_Match_Score__c >= 80
                AND Interview_Requested__c = false
                AND Status = 'Interested'];

			System.debug('Ready for Interview: ' + data.readyForInterview);
            
            // Get subscription info
            data.subscriptionTier = SubscriptionService.getSubscriptionTier(accountId);
            
            System.debug('Subscription Tier: ' + data.subscriptionTier);

	        System.debug('--- getMetrics END ---');
            
            res.statusCode = 200;
            res.responseBody = Blob.valueOf(JSON.serialize(
                new DashboardResponse(true, data, 'Dashboard metrics retrieved')
            ));
            
        } catch (Exception e) {
            res.statusCode = 500;
            res.responseBody = Blob.valueOf(JSON.serialize(
                new ErrorResponse(false, e.getMessage())
            ));
        }
    }
    
    private static void getActivity(String accountId, RestResponse res) {
        try {
            
            System.debug('--- getActivity START ---');
	        System.debug('AccountId: ' + accountId);
            
            Integer queryLimit = 10;
            String limitParam = RestContext.request.params.get('limit');
            if (String.isNotBlank(limitParam)) {
                queryLimit = Integer.valueOf(limitParam);
            }
            
            List<ActivityItem> activities = new List<ActivityItem>();
            
            // New candidates
            for (CampaignMember member : [
                SELECT Id, Contact.FirstName, Interest_Date__c, Campaign.Name
                FROM CampaignMember
                WHERE Campaign.Employer__c = :accountId
                AND Campaign.RecordType.DeveloperName = 'Talent_Pool'
                ORDER BY Interest_Date__c DESC
                LIMIT :queryLimit
            ]) {
                System.debug('Activity Member: ' + member.Id + ' - ' + member.Contact.FirstName);
                activities.add(new ActivityItem(
                    'candidate_interested',
                    member.Contact.FirstName + ' is interested in ' + member.Campaign.Name,
                    member.Interest_Date__c,
                    member.Id
                ));
            }
            
            System.debug('Total activities: ' + activities.size());
            
            // Sort by date
            activities.sort();
            
            res.statusCode = 200;
            res.responseBody = Blob.valueOf(JSON.serialize(
                new ActivityListResponse(true, activities, 'Recent activity retrieved')
            ));
            
        } catch (Exception e) {
            res.statusCode = 500;
            res.responseBody = Blob.valueOf(JSON.serialize(
                new ErrorResponse(false, e.getMessage())
            ));
        }
    }
    
    private static void getRecommendations(String accountId, RestResponse res) {
        try {
            System.debug('--- getRecommendations START ---');
			System.debug('AccountId: ' + accountId);
            
            List<FlintRecommendation> recommendations = new List<FlintRecommendation>();
            
            // Check for candidates ready for interview
            Integer readyForInterview = [SELECT COUNT() FROM CampaignMember 
                WHERE Campaign.Employer__c = :accountId 
                AND AI_Match_Score__c >= 80
                AND Interview_Requested__c = false
                AND Status = 'Interested'];
            System.debug('Ready for Interview count: ' + readyForInterview);
            
            if (readyForInterview > 0) {
                recommendations.add(new FlintRecommendation(
                    'interview_ready',
                    'You have ' + readyForInterview + ' high-match candidates ready for interview',
                    'Schedule Interviews',
                    '/talent-pools'
                ));
            }
            
            // Check for incomplete profile
            List<Account> accounts = [SELECT Profile_Completion__c FROM Account WHERE Id = :accountId LIMIT 1];
            if (!accounts.isEmpty()) {
                Account employer = accounts[0];
                if (employer.Profile_Completion__c == null || employer.Profile_Completion__c < 80) {
                    recommendations.add(new FlintRecommendation(
                        'complete_profile',
                        'Complete your company profile to attract more candidates',
                        'Complete Profile',
                        '/company'
                    ));
                }
            }
            
            // Check if no active jobs
            Integer activeJobs = [SELECT COUNT() FROM Campaign 
                WHERE Employer__c = :accountId 
                AND RecordType.DeveloperName = 'Talent_Pool' 
                AND IsActive = true];
            System.debug('Active Jobs count: ' + activeJobs);
            
            if (activeJobs == 0) {
                recommendations.add(new FlintRecommendation(
                    'create_job',
                    'Create your first job posting to start matching candidates',
                    'Post a Job',
                    '/jobs/new'
                ));
            }
            
            res.statusCode = 200;
            res.responseBody = Blob.valueOf(JSON.serialize(
                new RecommendationListResponse(true, recommendations, 'Recommendations retrieved')
            ));
            
        } catch (Exception e) {
            res.statusCode = 500;
            res.responseBody = Blob.valueOf(JSON.serialize(
                new ErrorResponse(false, e.getMessage())
            ));
        }
    }
    
    private static void getEvents(String accountId, RestResponse res) {
        try {
            Integer queryLimit = 10;
            String limitParam = RestContext.request.params.get('limit');
            if (String.isNotBlank(limitParam)) {
                queryLimit = Integer.valueOf(limitParam);
            }
            
            List<CalendarEvent> events = new List<CalendarEvent>();
            
            // Get scheduled interviews
            for (Task t : [
                SELECT Id, Subject, ActivityDate, WhatId
                FROM Task
                WHERE What.Type = 'Account' AND WhatId = :accountId
                AND ActivityDate >= TODAY
                AND Subject LIKE '%Interview%'
                ORDER BY ActivityDate
                LIMIT :queryLimit
            ]) {
                events.add(new CalendarEvent(t.Id, t.Subject, t.ActivityDate, 'interview'));
            }

            for (Rescue_Opportunity__c rescue : [
                SELECT Id, Contact__r.Name, Interview_Date__c, Status__c,
                       Candidate_Availability_Start__c, Candidate_Availability_End__c
                FROM Rescue_Opportunity__c
                WHERE Account__c = :accountId
                AND Status__c IN ('Scheduled', 'Confirmed')
                ORDER BY Interview_Date__c ASC NULLS LAST, CreatedDate DESC
                LIMIT :queryLimit
            ]) {
                String title = 'Interview - ' + (rescue.Contact__r == null ? 'Candidate' : rescue.Contact__r.Name);
                Date eventDate = rescue.Interview_Date__c == null ? Date.today() : rescue.Interview_Date__c.date();
                events.add(new CalendarEvent(rescue.Id, title, eventDate, 'interview'));
            }
            
            res.statusCode = 200;
            res.responseBody = Blob.valueOf(JSON.serialize(
                new EventListResponse(true, events, 'Upcoming events retrieved')
            ));
            
        } catch (Exception e) {
            res.statusCode = 500;
            res.responseBody = Blob.valueOf(JSON.serialize(
                new ErrorResponse(false, e.getMessage())
            ));
        }
    }
    
    // ==================== RESPONSE CLASSES ====================
    
    global class ErrorResponse {
        public Boolean success;
        public String message;
        
        public ErrorResponse(Boolean success, String message) {
            this.success = success;
            this.message = message;
        }
    }
    
    global class DashboardResponse {
        public Boolean success;
        public DashboardData data;
        public String message;
        
        public DashboardResponse(Boolean success, DashboardData data, String message) {
            this.success = success;
            this.data = data;
            this.message = message;
        }
    }
    
    global class ActivityListResponse {
        public Boolean success;
        public List<ActivityItem> activities;
        public String message;
        
        public ActivityListResponse(Boolean success, List<ActivityItem> activities, String message) {
            this.success = success;
            this.activities = activities;
            this.message = message;
        }
    }
    
    global class RecommendationListResponse {
        public Boolean success;
        public List<FlintRecommendation> recommendations;
        public String message;
        
        public RecommendationListResponse(Boolean success, List<FlintRecommendation> recommendations, String message) {
            this.success = success;
            this.recommendations = recommendations;
            this.message = message;
        }
    }
    
    global class EventListResponse {
        public Boolean success;
        public List<CalendarEvent> events;
        public String message;
        
        public EventListResponse(Boolean success, List<CalendarEvent> events, String message) {
            this.success = success;
            this.events = events;
            this.message = message;
        }
    }
    
    public class DashboardData {
        public Integer activeJobs;
        public Integer talentPoolSize;
        public Integer newCandidatesThisWeek;
        public Integer pendingInterviews;
        public Integer pendingOffers;
        public Integer readyForInterview;
        public String subscriptionTier;
    }
    
    public class ActivityItem implements Comparable {
        public String type;
        public String message;
        public DateTime timestamp;
        public Id recordId;
        
        public ActivityItem(String type, String message, DateTime timestamp, Id recordId) {
            this.type = type;
            this.message = message;
            this.timestamp = timestamp;
            this.recordId = recordId;
        }
        
        public Integer compareTo(Object other) {
            ActivityItem otherItem = (ActivityItem) other;
            if (this.timestamp > otherItem.timestamp) return -1;
            if (this.timestamp < otherItem.timestamp) return 1;
            return 0;
        }
    }
    
    public class FlintRecommendation {
        public String type;
        public String message;
        public String actionLabel;
        public String actionUrl;
        
        public FlintRecommendation(String type, String message, String actionLabel, String actionUrl) {
            this.type = type;
            this.message = message;
            this.actionLabel = actionLabel;
            this.actionUrl = actionUrl;
        }
    }
    
    public class CalendarEvent {
        public Id eventId;
        public String title;
        public Date eventDate;
        public String eventType;
        
        public CalendarEvent(Id eventId, String title, Date eventDate, String eventType) {
            this.eventId = eventId;
            this.title = title;
            this.eventDate = eventDate;
            this.eventType = eventType;
        }
    }
}