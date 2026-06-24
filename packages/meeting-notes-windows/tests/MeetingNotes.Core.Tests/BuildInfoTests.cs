using MeetingNotes.Core;

namespace MeetingNotes.Core.Tests;

public class BuildInfoTests
{
    [Fact]
    public void Name_is_set()
    {
        Assert.False(string.IsNullOrWhiteSpace(BuildInfo.Name));
    }
}