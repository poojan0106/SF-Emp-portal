// ============================================================================
// FILE 4: JobListingRESTAPI.cls
// REST endpoints for React frontend (rezourcer.ai/jobs)
// ============================================================================
@RestResource(urlMapping='/api/v1/jobs/*')
global with sharing class JobListingRESTAPI {

    @HttpGet
    global static void getJobs() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        try {
            String path = req.requestURI.substringAfter('/api/v1/jobs');

            if (String.isNotBlank(path) && path.length() > 1) {
                String cId = path.substringAfter('/');
                res.responseBody = Blob.valueOf(
                    JSON.serialize(JobListingService.getJobDetail(cId))
                );
            } else {
                Id acctId = req.params.get('accountId');
                JobListingDTO.JobFilter f = new JobListingDTO.JobFilter();
                f.status = req.params.containsKey('status')
                    ? req.params.get('status') : 'All';
                f.searchTerm = req.params.get('search');
                f.recordType = req.params.get('recordType');
                f.sortField = req.params.get('sortField');
                f.sortDirection = req.params.get('sortDir');
                f.pageSize = req.params.containsKey('pageSize')
                    ? Integer.valueOf(req.params.get('pageSize')) : 20;
                f.pageNumber = req.params.containsKey('page')
                    ? Integer.valueOf(req.params.get('page')) : 1;

                res.responseBody = Blob.valueOf(
                    JSON.serialize(JobListingService.getJobs(acctId, f))
                );
            }
            res.statusCode = 200;
        } catch (Exception e) {
            res.statusCode = 500;
            res.responseBody = Blob.valueOf(JSON.serialize(
                new Map<String, String>{ 'error' => e.getMessage() }
            ));
        }
    }

    @HttpPost
    global static void createJob() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');
        try {
            
            String action = req.params.get('action');
            // POST /api/v1/jobs?action=duplicate&jobId={jobId}
            if (action == 'duplicate') {
                String jobId = req.params.get('jobId');
                Id newId = JobListingService.duplicateJob(jobId);
                res.statusCode = 201;
                res.responseBody = Blob.valueOf(JSON.serialize(
                    new Map<String, String>{ 'id' => newId }
                ));
            }
            // POST /api/v1/jobs - Create new job
            else{
            JobListingDTO.JobCreateRequest request =
                (JobListingDTO.JobCreateRequest)JSON.deserialize(
                    RestContext.request.requestBody.toString(),
                    JobListingDTO.JobCreateRequest.class
                );
            Id newId = JobListingService.createJob(request);
            res.statusCode = 201;
            res.responseBody = Blob.valueOf(JSON.serialize(
                new Map<String, String>{ 'id' => newId }
            ));
           }
        } catch (Exception e) {
            res.statusCode = 400;
            res.responseBody = Blob.valueOf(JSON.serialize(
                new Map<String, String>{ 'error' => e.getMessage() }
            ));
        }
    }

    @HttpPatch
    global static void updateJob() {
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');
        try {
            String cId = RestContext.request.requestURI.substringAfterLast('/');
            JobListingDTO.JobCreateRequest request =
                (JobListingDTO.JobCreateRequest)JSON.deserialize(
                    RestContext.request.requestBody.toString(),
                    JobListingDTO.JobCreateRequest.class
                );
            JobListingService.updateJob(cId, request);
            res.statusCode = 200;
            res.responseBody = Blob.valueOf('{"success":true}');
        } catch (Exception e) {
            res.statusCode = 400;
            res.responseBody = Blob.valueOf(JSON.serialize(
                new Map<String, String>{ 'error' => e.getMessage() }
            ));
        }
    }
}