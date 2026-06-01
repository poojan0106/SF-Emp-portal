// ========================================
// REST API Controller for Job Creation
// ========================================
@RestResource(urlMapping='/jobs/create')
global class JobCreationController {
  
  @HttpPost
  global static void createJob() {
    try {
      RestRequest req = RestContext.request;
      RestResponse res = RestContext.response;
      
      // Deserialize request body to JobCreationRequest
      JobCreationService.JobCreationRequest jobReq = (JobCreationService.JobCreationRequest) JSON.deserialize(
        req.requestBody.toString(),
        JobCreationService.JobCreationRequest.class
      );
      
      // Call service to create campaign
      JobCreationService.JobCreationResponse response = JobCreationService.createJobCampaign(jobReq);
      
      // Convert response to Map for serialization
      Map<String, Object> responseMap = new Map<String, Object>{
        'success' => response.success,
        'campaignId' => response.campaignId,
        'status' => response.status,
        'message' => response.message
      };
      
      // Send success response
      res.statusCode = 200;
      res.responseBody = Blob.valueOf(JSON.serialize(responseMap));
      
    } catch (Exception e) {
      // Handle error
      RestContext.response.statusCode = 400;
      Map<String, Object> errorMap = new Map<String, Object>{
        'success' => false,
        'error' => 'Error creating job: ' + e.getMessage()
      };
      RestContext.response.responseBody = Blob.valueOf(JSON.serialize(errorMap));
    }
  }
}