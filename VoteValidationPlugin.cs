using System;
using Microsoft.Xrm.Sdk;

namespace GameChanger.Plugins
{
    public class VoteValidationPlugin : IPlugin
    {
        private const int Fan = 100000000;
        private const int Judge = 100000001;
        private const int HeadJudge = 100000002;

        public void Execute(IServiceProvider serviceProvider)
        {
            ITracingService tracingService =
                (ITracingService)serviceProvider.GetService(
                    typeof(ITracingService));

            IPluginExecutionContext context =
                (IPluginExecutionContext)serviceProvider.GetService(
                    typeof(IPluginExecutionContext));

            IOrganizationServiceFactory serviceFactory =
                (IOrganizationServiceFactory)serviceProvider.GetService(
                    typeof(IOrganizationServiceFactory));

            IOrganizationService service =
                serviceFactory.CreateOrganizationService(context.UserId);

            tracingService.Trace("VoteValidationPlugin started.");

            // Confirm that the plugin received a Target record.
            if (!context.InputParameters.Contains("Target") ||
                !(context.InputParameters["Target"] is Entity))
            {
                tracingService.Trace(
                    "Target was missing or was not an Entity.");

                return;
            }

            Entity target =
                (Entity)context.InputParameters["Target"];

            tracingService.Trace(
                $"Target table: {target.LogicalName}");

            // Confirm that the Target is a Vote record.
            if (target.LogicalName != "new_vote")
            {
                tracingService.Trace(
                    "Target table was not new_vote. Plugin execution stopped.");

                return;
            }

            // Validate required Vote fields.
            string[] requiredFields =
            {
                "new_player",
                "new_tournament",
                "new_team",
                "new_division",
                "new_votecategory",
                "new_votertype"
            };

            foreach (string field in requiredFields)
            {
                if (!target.Attributes.Contains(field) ||
                    target[field] == null)
                {
                    tracingService.Trace(
                        $"Validation failed. Missing required field: {field}");

                    throw new InvalidPluginExecutionException(
                        $"The vote cannot be submitted because the required field '{field}' is missing.");
                }
            }

            tracingService.Trace(
                "Required field validation passed.");

            // Retrieve the Voter Type choice value.
            OptionSetValue voterTypeOption =
                target.GetAttributeValue<OptionSetValue>("new_votertype");

            int voterType = voterTypeOption.Value;

            // Retrieve the Judge lookup.
            EntityReference judgeReference =
                target.GetAttributeValue<EntityReference>("new_judge");

            tracingService.Trace(
                $"Voter Type value: {voterType}");

            tracingService.Trace(
                judgeReference == null
                    ? "Judge lookup is empty."
                    : $"Judge lookup ID: {judgeReference.Id}");

            /*
             * Business rule:
             *
             * Fan:
             * Judge lookup must be empty.
             *
             * Judge or Head Judge:
             * Judge lookup is required.
             */

            if (voterType == Fan)
            {
                if (judgeReference != null)
                {
                    tracingService.Trace(
                        "Validation failed. A fan vote contained a Judge lookup.");

                    throw new InvalidPluginExecutionException(
                        "A fan vote cannot be connected to a Judge record.");
                }

                tracingService.Trace(
                    "Fan voter-type validation passed.");
            }
            else if (voterType == Judge ||
                     voterType == HeadJudge)
            {
                if (judgeReference == null)
                {
                    tracingService.Trace(
                        "Validation failed. A judge vote did not contain a Judge lookup.");

                    throw new InvalidPluginExecutionException(
                        "A Judge or Head Judge vote must be connected to a Judge record.");
                }

                tracingService.Trace(
                    "Judge voter-type validation passed.");
            }
            else
            {
                tracingService.Trace(
                    $"Validation failed. Unsupported Voter Type value: {voterType}");

                throw new InvalidPluginExecutionException(
                    "The selected Voter Type is not valid.");
            }

            tracingService.Trace(
                "VoteValidationPlugin completed successfully.");
        }
    }
}