public without sharing class CareerPathwaySyncService {
    private class GoalSpec {
        String horizon;
        String timeline;
        Integer minMonths;
        Integer maxMonths;
        Integer orderNumber;
        String goal;

        GoalSpec(String horizon, String timeline, Integer minMonths, Integer maxMonths, Integer orderNumber, String goal) {
            this.horizon = horizon;
            this.timeline = timeline;
            this.minMonths = minMonths;
            this.maxMonths = maxMonths;
            this.orderNumber = orderNumber;
            this.goal = goal;
        }
    }

    public static void syncForIntent(Id intentId) {
        if (intentId == null) return;

        Career_Intent__c intent = [
            SELECT Id, Contact__c, Candidate__c, Short_Term_Goal__c, Medium_Term_Goal__c,
                   Long_Term_Goal__c, Aspirational_Goal__c, Role_Title__c
            FROM Career_Intent__c
            WHERE Id = :intentId
            LIMIT 1
        ];

        Id candidateId = intent.Contact__c != null ? intent.Contact__c : intent.Candidate__c;
        if (candidateId == null) return;

        List<GoalSpec> goals = new List<GoalSpec>{
            new GoalSpec('Short-Term', '0 - 6 months', 0, 6, 1, intent.Short_Term_Goal__c),
            new GoalSpec('Medium-Term', '2 - 5 years', 24, 60, 2, intent.Medium_Term_Goal__c),
            new GoalSpec('Long-Term', '10+ years', 120, null, 3, intent.Long_Term_Goal__c),
            new GoalSpec('Aspirational', 'Dream role', null, null, 4, intent.Aspirational_Goal__c)
        };

        Set<Id> pathwayIds = new Set<Id>();
        List<Career_Pathway__c> existingPathways = [
            SELECT Id, Aspirational_Goal__c, Current_State__c, Status__c, Last_Updated__c
            FROM Career_Pathway__c
            WHERE Career_Intent__c = :intent.Id
            AND Candidate__c = :candidateId
            ORDER BY Last_Updated__c DESC NULLS LAST, LastModifiedDate DESC
        ];
        for (Career_Pathway__c pathway : existingPathways) {
            pathwayIds.add(pathway.Id);
        }

        Map<Id, List<Career_Pathway_Stage__c>> stagesByPathway = new Map<Id, List<Career_Pathway_Stage__c>>();
        if (!pathwayIds.isEmpty()) {
            for (Career_Pathway_Stage__c stage : [
                SELECT Id, Career_Pathway__c, Time_Horizon__c, Stage_Number__c, Stage_Title__c,
                       Target_Role__c, Status__c, Is_Current_Stage__c
                FROM Career_Pathway_Stage__c
                WHERE Career_Pathway__c IN :pathwayIds
                ORDER BY Stage_Number__c ASC NULLS LAST, CreatedDate ASC
            ]) {
                if (!stagesByPathway.containsKey(stage.Career_Pathway__c)) {
                    stagesByPathway.put(stage.Career_Pathway__c, new List<Career_Pathway_Stage__c>());
                }
                stagesByPathway.get(stage.Career_Pathway__c).add(stage);
            }
        }

        Map<String, Career_Pathway__c> pathwayByHorizon = new Map<String, Career_Pathway__c>();
        List<Career_Pathway__c> extraPathways = new List<Career_Pathway__c>();
        for (Career_Pathway__c pathway : existingPathways) {
            String horizon = horizonForPathway(pathway, stagesByPathway.get(pathway.Id));
            if (String.isBlank(horizon) || pathwayByHorizon.containsKey(horizon)) {
                extraPathways.add(pathway);
            } else {
                pathwayByHorizon.put(horizon, pathway);
            }
        }

        List<Career_Pathway__c> pathwaysToInsert = new List<Career_Pathway__c>();
        List<Career_Pathway__c> pathwaysToUpdate = new List<Career_Pathway__c>();
        for (GoalSpec spec : goals) {
            if (String.isBlank(spec.goal)) continue;

            Career_Pathway__c pathway = pathwayByHorizon.get(spec.horizon);
            if (pathway == null) {
                pathwaysToInsert.add(new Career_Pathway__c(
                    Candidate__c = candidateId,
                    Career_Intent__c = intent.Id,
                    Current_State__c = spec.horizon,
                    Aspirational_Goal__c = spec.goal,
                    Status__c = 'Active',
                    Stage_Count__c = 1,
                    Generated_Date__c = DateTime.now(),
                    Last_Updated__c = DateTime.now(),
                    AI_Model_Used__c = 'Blakeney sync'
                ));
            } else {
                pathway.Current_State__c = spec.horizon;
                pathway.Aspirational_Goal__c = spec.goal;
                pathway.Status__c = 'Active';
                pathway.Stage_Count__c = 1;
                pathway.Last_Updated__c = DateTime.now();
                pathwaysToUpdate.add(pathway);
            }
        }

        if (!pathwaysToInsert.isEmpty()) {
            insert pathwaysToInsert;
            Integer insertedIndex = 0;
            for (GoalSpec spec : goals) {
                if (String.isBlank(spec.goal) || pathwayByHorizon.containsKey(spec.horizon)) continue;
                pathwayByHorizon.put(spec.horizon, pathwaysToInsert[insertedIndex]);
                insertedIndex++;
            }
        }

        if (!pathwaysToUpdate.isEmpty()) update pathwaysToUpdate;

        List<Career_Pathway_Stage__c> stagesToInsert = new List<Career_Pathway_Stage__c>();
        List<Career_Pathway_Stage__c> stagesToUpdate = new List<Career_Pathway_Stage__c>();
        List<Career_Pathway_Stage__c> stagesToDelete = new List<Career_Pathway_Stage__c>();

        for (GoalSpec spec : goals) {
            if (String.isBlank(spec.goal)) continue;
            Career_Pathway__c pathway = pathwayByHorizon.get(spec.horizon);
            if (pathway == null) continue;

            List<Career_Pathway_Stage__c> existingStages = stagesByPathway.get(pathway.Id);
            Career_Pathway_Stage__c stage = existingStages == null || existingStages.isEmpty() ? null : existingStages[0];
            if (stage == null) {
                stagesToInsert.add(buildStage(pathway.Id, spec));
            } else {
                applyStageValues(stage, spec);
                stagesToUpdate.add(stage);
                for (Integer i = 1; i < existingStages.size(); i++) {
                    stagesToDelete.add(existingStages[i]);
                }
            }
        }

        for (Career_Pathway__c extra : extraPathways) {
            extra.Status__c = 'Archived';
            extra.Last_Updated__c = DateTime.now();
        }
        if (!extraPathways.isEmpty()) update extraPathways;
        if (!stagesToDelete.isEmpty()) delete stagesToDelete;
        if (!stagesToInsert.isEmpty()) insert stagesToInsert;
        if (!stagesToUpdate.isEmpty()) update stagesToUpdate;
    }

    private static Career_Pathway_Stage__c buildStage(Id pathwayId, GoalSpec spec) {
        Career_Pathway_Stage__c stage = new Career_Pathway_Stage__c(Career_Pathway__c = pathwayId);
        applyStageValues(stage, spec);
        return stage;
    }

    private static void applyStageValues(Career_Pathway_Stage__c stage, GoalSpec spec) {
        stage.Name = 'Stage ' + spec.orderNumber + ': ' + truncate(spec.goal, 70);
        stage.Stage_Number__c = spec.orderNumber;
        stage.Stage_Title__c = truncate(spec.goal, 255);
        stage.Target_Role__c = truncate(spec.goal, 255);
        stage.Status__c = spec.orderNumber == 1 ? 'In Progress' : 'Not Started';
        stage.Is_Current_Stage__c = spec.orderNumber == 1;
        stage.Time_Horizon__c = spec.horizon;
        stage.Estimated_Timeline__c = spec.timeline;
        stage.Timeline_Months_Min__c = spec.minMonths;
        stage.Timeline_Months_Max__c = spec.maxMonths;
        stage.Milestone_Notes__c = buildMilestoneNotes(spec.goal);
        stage.Description__c = 'Career stage generated from saved goal: ' + spec.goal;
        stage.Confidence_Score__c = 75;
    }

    private static String horizonForPathway(Career_Pathway__c pathway, List<Career_Pathway_Stage__c> stages) {
        if (stages != null) {
            for (Career_Pathway_Stage__c stage : stages) {
                if (String.isNotBlank(stage.Time_Horizon__c)) return stage.Time_Horizon__c;
            }
        }
        if (new Set<String>{ 'Short-Term', 'Medium-Term', 'Long-Term', 'Aspirational' }.contains(pathway.Current_State__c)) {
            return pathway.Current_State__c;
        }
        return null;
    }

    private static String buildMilestoneNotes(String goal) {
        return String.join(new List<String>{
            'Blakeney assessment: focus on practical proof for ' + goal + '.',
            '1. Clarify required skills, credentials, experience, and proof employers expect.',
            '2. Compare requirements with current profile and list biggest gaps.',
            '3. Complete one course, certificate, project, or work assignment that closes first gap.',
            '4. Build visible proof: portfolio item, measurable work result, case study, or recommendation.',
            '5. Get feedback from someone already working near this goal and adjust plan.',
            '6. Apply for roles, projects, or internal opportunities that move you closer.',
            '7. Track progress regularly and update profile with new evidence.'
        }, '\n');
    }

    private static String truncate(String value, Integer maxLength) {
        String text = value == null ? '' : value.trim();
        return text.length() > maxLength ? text.substring(0, maxLength) : text;
    }
}