using Microsoft.Xrm.Sdk;
using Microsoft.Xrm.Sdk.Query;
using System;

namespace GameChanger.Plugins
{
    public class VoteResultPlugin : IPlugin
    {
        public void Execute(IServiceProvider serviceProvider)
        {
            var context = (IPluginExecutionContext)serviceProvider.GetService(typeof(IPluginExecutionContext));

            if (context.MessageName != "Create")
                return;

            if (!context.InputParameters.Contains("Target") ||
                !(context.InputParameters["Target"] is Entity))
                return;

            Entity target = (Entity)context.InputParameters["Target"];

            if (target.LogicalName != "new_vote")
                return;

            ITracingService tracingService =
                (ITracingService)serviceProvider.GetService(typeof(ITracingService));

            IOrganizationServiceFactory serviceFactory =
                (IOrganizationServiceFactory)serviceProvider.GetService(typeof(IOrganizationServiceFactory));

            IOrganizationService service =
                serviceFactory.CreateOrganizationService(context.UserId);

            tracingService.Trace("VoteResultPlugin started.");
            tracingService.Trace("Vote ID: " + target.Id);

            Entity vote = service.Retrieve(
                "new_vote",
                target.Id,
                new ColumnSet(
                    "new_player",
                    "new_tournament",
                    "new_team",
                    "new_division",
                    "new_votecategory",
                    "new_votertype"
                )
            );

            EntityReference playerRef = vote.GetAttributeValue<EntityReference>("new_player");
            EntityReference tournamentRef = vote.GetAttributeValue<EntityReference>("new_tournament");
            EntityReference teamRef = vote.GetAttributeValue<EntityReference>("new_team");
            EntityReference divisionRef = vote.GetAttributeValue<EntityReference>("new_division");
            OptionSetValue voteCategory = vote.GetAttributeValue<OptionSetValue>("new_votecategory");
            OptionSetValue voterType = vote.GetAttributeValue<OptionSetValue>("new_votertype");

            if (playerRef == null || tournamentRef == null || teamRef == null ||
                divisionRef == null || voteCategory == null || voterType == null)
            {
                tracingService.Trace("Missing required vote data. Plugin stopped.");
                return;
            }

            string categoryName = "Unknown Category";

            if (voteCategory.Value == 122680000)
                categoryName = "MVP";
            else if (voteCategory.Value == 122680001)
                categoryName = "Best Offensive Player";
            else if (voteCategory.Value == 122680002)
                categoryName = "Best Defensive Player";
            else if (voteCategory.Value == 122680003)
                categoryName = "Fan Favorite";

            string resultName =
                playerRef.Name + " - " +
                categoryName + " - " +
                divisionRef.Name;

            tracingService.Trace("Player ID: " + playerRef.Id);
            tracingService.Trace("Tournament ID: " + tournamentRef.Id);
            tracingService.Trace("Team ID: " + teamRef.Id);
            tracingService.Trace("Division ID: " + divisionRef.Id);
            tracingService.Trace("Vote Category Value: " + voteCategory.Value);
            tracingService.Trace("Voter Type Value: " + voterType.Value);
            tracingService.Trace("Result Name: " + resultName);

            QueryExpression resultQuery = new QueryExpression("new_result");
            resultQuery.ColumnSet = new ColumnSet(
                "new_fanvotecount",
                "new_judgevotecount",
                "new_weightedscore",
                "new_resultname"
            );

            resultQuery.Criteria.AddCondition("new_player", ConditionOperator.Equal, playerRef.Id);
            resultQuery.Criteria.AddCondition("new_tournament", ConditionOperator.Equal, tournamentRef.Id);
            resultQuery.Criteria.AddCondition("new_division", ConditionOperator.Equal, divisionRef.Id);
            resultQuery.Criteria.AddCondition("new_category", ConditionOperator.Equal, voteCategory.Value);

            EntityCollection existingResults = service.RetrieveMultiple(resultQuery);

            tracingService.Trace("Matching Result records found: " + existingResults.Entities.Count);

            int fanVotes = 0;
            int judgeVotes = 0;
            Entity resultToSave;

            if (existingResults.Entities.Count > 0)
            {
                resultToSave = existingResults.Entities[0];

                fanVotes = resultToSave.GetAttributeValue<int?>("new_fanvotecount") ?? 0;
                judgeVotes = resultToSave.GetAttributeValue<int?>("new_judgevotecount") ?? 0;

                tracingService.Trace("Existing result found.");
            }
            else
            {
                resultToSave = new Entity("new_result");

                resultToSave["new_player"] = playerRef;
                resultToSave["new_tournament"] = tournamentRef;
                resultToSave["new_team"] = teamRef;
                resultToSave["new_division"] = divisionRef;
                resultToSave["new_category"] = voteCategory;

                tracingService.Trace("No result found. Creating new result.");
            }

            resultToSave["new_resultname"] = resultName;

            if (voterType.Value == 100000000) // Fan
            {
                fanVotes++;
                tracingService.Trace("Fan vote counted.");
            }
            else if (voterType.Value == 100000001) // Judge
            {
                judgeVotes++;
                tracingService.Trace("Judge vote counted.");
            }
            else if (voterType.Value == 100000002) // Head Judge
            {
                judgeVotes++;
                tracingService.Trace("Head Judge vote counted as judge vote.");
            }
            else
            {
                tracingService.Trace("Unknown voter type. Plugin stopped.");
                return;
            }

            int weightedScore = fanVotes + (judgeVotes * 10);

            resultToSave["new_fanvotecount"] = fanVotes;
            resultToSave["new_judgevotecount"] = judgeVotes;
            resultToSave["new_weightedscore"] = weightedScore;

            tracingService.Trace("Fan Votes: " + fanVotes);
            tracingService.Trace("Judge Votes: " + judgeVotes);
            tracingService.Trace("Weighted Score: " + weightedScore);

            if (existingResults.Entities.Count > 0)
            {
                service.Update(resultToSave);
                tracingService.Trace("Result record updated.");
            }
            else
            {
                service.Create(resultToSave);
                tracingService.Trace("Result record created.");
            }

            tracingService.Trace("VoteResultPlugin finished.");
        }
    }
}