/**
 * TalentPoolRestResource
 * REST API wrapper for TalentPoolController to expose methods to frontend
 */
@RestResource(urlMapping='/talent-pool/*')
global with sharing class TalentPoolRestResource {
    
    @HttpGet
    global static void doGet() {
        RestRequest request = RestContext.request;
        String endpoint = request.requestUri.substringAfterLast('/').split('\\?')[0];
        
        try {
            if (endpoint == 'pools') {
                String accountId = request.params.get('accountId');
                getPoolsResponse(accountId);
            } else if (endpoint == 'metrics') {
                String poolId = request.params.get('poolId');
                getMetricsResponse(poolId);
            } else {
                sendResponse(400, 'Invalid endpoint');
            }
        } catch (Exception e) {
            sendErrorResponse(e);
        }
    }
    
    @HttpPost
    global static void doPost() {
        RestRequest request = RestContext.request;
        String endpoint = request.requestUri.substringAfterLast('/');
        String body = request.requestBody.toString();
        
        try {
            if (endpoint == 'candidates') {
                getCandidatesResponse(body);
            } else if (endpoint == 'unlock-profile') {
                unlockProfileResponse(body);
            } else if (endpoint == 'request-interview') {
                requestInterviewResponse(body);
            } else {
                sendResponse(400, 'Invalid endpoint');
            }
        } catch (DmlException e) {
            if (e.getMessage().contains('INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY')) {
                sendResponse(403, 'Insufficient subscription access');
            } else {
                sendErrorResponse(e);
            }
        } catch (Exception e) {
            sendErrorResponse(e);
        }
    }
    
    /**
     * GET /pools - Get all talent pools
     */
    private static void getPoolsResponse(String accountId) {
        if (String.isBlank(accountId)) {
            sendResponse(400, 'Missing accountId parameter');
            return;
        }
        
        List<TalentPoolController.TalentPoolWrapper> pools = TalentPoolController.getEmployerTalentPools(accountId);
        sendResponse(200, pools);
    }
    
    /**
     * POST /candidates - Get candidates with filtering and pagination
     */
    private static void getCandidatesResponse(String body) {
        CandidatesRequest request = (CandidatesRequest) JSON.deserialize(body, CandidatesRequest.class);
        
        if (String.isBlank(request.poolId)) {
            sendResponse(400, 'Missing poolId');
            return;
        }
        
        TalentPoolController.CandidateFilter filters = new TalentPoolController.CandidateFilter();
        if (request.filters != null) {
            filters.location = request.filters.location;
            filters.minExperience = request.filters.minExperience;
            filters.maxExperience = request.filters.maxExperience;
            filters.skills = request.filters.skills;
            filters.availability = request.filters.availability;
        }
        
        Integer pageNumber = request.pageNumber != null ? request.pageNumber : 1;
        Integer pageSize = request.pageSize != null ? request.pageSize : 10;
        
        TalentPoolController.CandidateListResult result = TalentPoolController.getPoolCandidates(
            request.poolId,
            filters,
            pageNumber,
            pageSize
        );
        
        sendResponse(200, result);
    }
    
    /**
     * POST /unlock-profile - Unlock candidate profile
     */
    private static void unlockProfileResponse(String body) {
        UnlockRequest request = (UnlockRequest) JSON.deserialize(body, UnlockRequest.class);
        
        if (String.isBlank(request.campaignMemberId) || String.isBlank(request.accountId)) {
            sendResponse(400, 'Missing required fields');
            return;
        }
        
        try {
            TalentPoolController.CandidateWrapper candidate = TalentPoolController.unlockCandidateProfile(
                request.campaignMemberId,
                request.accountId
            );
            sendResponse(200, candidate);
        } catch (Exception e) {
            if (e.getMessage().contains('Feature access denied')) {
                sendResponse(403, 'Your subscription does not include this feature');
            } else {
                throw e;
            }
        }
    }
    
    /**
     * POST /request-interview - Request interview with candidate
     */
    private static void requestInterviewResponse(String body) {
        InterviewRequest request = (InterviewRequest) JSON.deserialize(body, InterviewRequest.class);
        
        if (String.isBlank(request.campaignMemberId) || String.isBlank(request.accountId)) {
            sendResponse(400, 'Missing required fields');
            return;
        }
        
        try {
            TalentPoolController.requestInterview(
                request.campaignMemberId,
                request.accountId,
                request.message
            );
            sendResponse(200, new Map<String, String>{'status' => 'success', 'message' => 'Interview request sent'});
        } catch (Exception e) {
            if (e.getMessage().contains('Feature access denied')) {
                sendResponse(403, 'Your subscription does not include this feature');
            } else {
                throw e;
            }
        }
    }
    
    /**
     * GET /metrics - Get pool metrics
     */
    private static void getMetricsResponse(String poolId) {
        if (String.isBlank(poolId)) {
            sendResponse(400, 'Missing poolId parameter');
            return;
        }
        
        TalentPoolController.PoolMetrics metrics = TalentPoolController.getPoolMetrics(poolId);
        sendResponse(200, metrics);
    }
    
    /**
     * Send JSON response
     */
    private static void sendResponse(Integer statusCode, Object data) {
        RestResponse response = RestContext.response;
        response.statusCode = statusCode;
        response.addHeader('Content-Type', 'application/json');
        response.responseBody = Blob.valueOf(JSON.serialize(data));
    }
    
    /**
     * Send error response
     */
    private static void sendErrorResponse(Exception e) {
        Map<String, String> error = new Map<String, String>{
            'error' => e.getTypeName(),
            'message' => e.getMessage(),
            'line' => String.valueOf(e.getLineNumber())
        };
        sendResponse(500, error);
    }
    
    // Request wrapper classes
    global class CandidatesRequest {
        global String poolId;
        global FilterObject filters;
        global Integer pageNumber;
        global Integer pageSize;
    }
    
    global class FilterObject {
        global List<String> skills;
        global String location;
        global Integer minExperience;
        global Integer maxExperience;
        global String availability;
    }
    
    global class UnlockRequest {
        global String campaignMemberId;
        global String accountId;
    }
    
    global class InterviewRequest {
        global String campaignMemberId;
        global String accountId;
        global String message;
    }
}