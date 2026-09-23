using GitHub.DistributedTask.Pipelines;
using GitHub.Runner.Worker.Container;
using System;
using System.IO;
using Xunit;

namespace GitHub.Runner.Common.Tests.Worker
{
    public sealed class ContainerInfoL0
    {
        [Fact]
        [Trait("Level", "L0")]
        [Trait("Category", "Worker")]
        public void TranslateToContainerPathUsesCanonicalPathsForOverrideDirectories()
        {
            var tempOverride = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("D"), "runner-temp");
            var actionsOverride = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("D"), "runner-actions");

            try
            {
                Environment.SetEnvironmentVariable(Constants.Variables.Agent.TempDirectory, tempOverride);
                Environment.SetEnvironmentVariable(Constants.Variables.Agent.ActionsDirectory, actionsOverride);

                using var hostContext = new TestHostContext(this, nameof(TranslateToContainerPathUsesCanonicalPathsForOverrideDirectories));
                var container = new ContainerInfo(hostContext, new JobContainer { Image = "ubuntu:22.04" });

                Assert.Equal("/__w/_temp", container.TranslateToContainerPath(hostContext.GetDirectory(WellKnownDirectory.Temp)));
                Assert.Equal("/__w/_temp/scripts/test.sh", container.TranslateToContainerPath(Path.Combine(hostContext.GetDirectory(WellKnownDirectory.Temp), "scripts", "test.sh")));
                Assert.Equal("/__w/_actions", container.TranslateToContainerPath(hostContext.GetDirectory(WellKnownDirectory.Actions)));
                Assert.Equal("/__w/_actions/owner/repo", container.TranslateToContainerPath(Path.Combine(hostContext.GetDirectory(WellKnownDirectory.Actions), "owner", "repo")));
            }
            finally
            {
                Environment.SetEnvironmentVariable(Constants.Variables.Agent.TempDirectory, null);
                Environment.SetEnvironmentVariable(Constants.Variables.Agent.ActionsDirectory, null);
            }
        }
    }
}
