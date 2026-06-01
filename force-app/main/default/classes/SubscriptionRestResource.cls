/**
 * SubscriptionRestResource
 * REST API wrapper for SubscriptionController to expose subscription methods to frontend
 */
@RestResource(urlMapping='/subscription/*')
global with sharing class SubscriptionRestResource {
    
    @HttpGet
    global static void doGet() {
        RestRequest request = RestContext.request;
        String endpoint = request.requestUri.substringAfterLast('/');
        
        try {
            if (endpoint == 'subscription') {
                String accountId = request.params.get('accountId');
                getSubscriptionResponse(accountId);
            } else if (endpoint == 'payment-history') {
                String accountId = request.params.get('accountId');
                getPaymentHistoryResponse(accountId);
            } else if (endpoint == 'feature-limits') {
                String accountId = request.params.get('accountId');
                getFeatureLimitsResponse(accountId);
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
            if (endpoint == 'checkout-session') {
                createCheckoutSessionResponse(body);
            } else if (endpoint == 'portal-session') {
                createPortalSessionResponse(body);
            } else if (endpoint == 'start-trial') {
                startFreeTrialResponse(body);
            } else {
                sendResponse(400, 'Invalid endpoint');
            }
        } catch (SubscriptionService.SubscriptionException e) {
            sendResponse(403, e.getMessage());
        } catch (Exception e) {
            sendErrorResponse(e);
        }
    }
    
    /**
     * GET /subscription - Get subscription details for an account
     */
    private static void getSubscriptionResponse(String accountId) {
        if (String.isBlank(accountId)) {
            sendResponse(400, 'Missing accountId parameter');
            return;
        }
        
        SubscriptionController.SubscriptionWrapper subscription = SubscriptionController.getSubscription((Id) accountId);
        sendResponse(200, subscription);
    }
    
    /**
     * GET /payment-history - Get payment history for an account
     */
    private static void getPaymentHistoryResponse(String accountId) {
        if (String.isBlank(accountId)) {
            sendResponse(400, 'Missing accountId parameter');
            return;
        }
        
        List<Payment_Transaction__c> payments = SubscriptionController.getPaymentHistory((Id) accountId);
        sendResponse(200, payments);
    }
    
    /**
     * GET /feature-limits - Get feature limits based on subscription tier
     */
    private static void getFeatureLimitsResponse(String accountId) {
        if (String.isBlank(accountId)) {
            sendResponse(400, 'Missing accountId parameter');
            return;
        }
        
        Map<String, Object> limits = SubscriptionController.getFeatureLimits((Id) accountId);
        sendResponse(200, limits);
    }
    
    /**
     * POST /checkout-session - Create a Stripe checkout session
     */
    private static void createCheckoutSessionResponse(String body) {
        CheckoutSessionRequest request = (CheckoutSessionRequest) JSON.deserialize(body, CheckoutSessionRequest.class);
        
        if (String.isBlank(request.accountId) || String.isBlank(request.priceId)) {
            sendResponse(400, 'Missing required fields: accountId, priceId');
            return;
        }
        
        try {
            String checkoutUrl = SubscriptionController.createCheckoutSession(
                (Id) request.accountId,
                request.priceId,
                request.successUrl,
                request.cancelUrl
            );
            
            Map<String, String> response = new Map<String, String>{
                'checkoutUrl' => checkoutUrl
            };
            sendResponse(200, response);
        } catch (AuraHandledException e) {
            sendResponse(400, e.getMessage());
        }
    }
    
    /**
     * POST /portal-session - Create a Stripe billing portal session
     */
    private static void createPortalSessionResponse(String body) {
        PortalSessionRequest request = (PortalSessionRequest) JSON.deserialize(body, PortalSessionRequest.class);
        
        if (String.isBlank(request.accountId)) {
            sendResponse(400, 'Missing required field: accountId');
            return;
        }
        
        try {
            String portalUrl = SubscriptionController.createPortalSession(
                (Id) request.accountId,
                request.returnUrl
            );
            
            Map<String, String> response = new Map<String, String>{
                'portalUrl' => portalUrl
            };
            sendResponse(200, response);
        } catch (AuraHandledException e) {
            sendResponse(400, e.getMessage());
        }
    }
    
    /**
     * POST /start-trial - Start a free trial for the account
     */
    private static void startFreeTrialResponse(String body) {
        StartTrialRequest request = (StartTrialRequest) JSON.deserialize(body, StartTrialRequest.class);
        
        if (String.isBlank(request.accountId)) {
            sendResponse(400, 'Missing required field: accountId');
            return;
        }
        
        try {
            SubscriptionController.startFreeTrial((Id) request.accountId);
            
            Map<String, String> response = new Map<String, String>{
                'status' => 'success',
                'message' => 'Free trial started successfully'
            };
            sendResponse(200, response);
        } catch (AuraHandledException e) {
            sendResponse(400, e.getMessage());
        }
    }
    
    /**
     * Send JSON response with status code
     */
    private static void sendResponse(Integer statusCode, Object data) {
        RestResponse response = RestContext.response;
        response.statusCode = statusCode;
        response.addHeader('Content-Type', 'application/json');
        response.responseBody = Blob.valueOf(JSON.serialize(data));
    }
    
    /**
     * Send error response with exception details
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
    global class CheckoutSessionRequest {
        global String accountId;
        global String priceId;
        global String successUrl;
        global String cancelUrl;
    }
    
    global class PortalSessionRequest {
        global String accountId;
        global String returnUrl;
    }
    
    global class StartTrialRequest {
        global String accountId;
    }
}