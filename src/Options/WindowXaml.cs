// The main window (copied from Scripts\Options.ps1: the same layout).
namespace RaintileOptions
{
    static class WindowXaml
    {
        public const string Text = @"<Window xmlns=""http://schemas.microsoft.com/winfx/2006/xaml/presentation""
        xmlns:x=""http://schemas.microsoft.com/winfx/2006/xaml""
        Title=""Raintile - Options"" Width=""1180"" Height=""800"" MinWidth=""960"" MinHeight=""580""
        WindowStartupLocation=""CenterScreen"" Background=""{StaticResource Bg}"" Foreground=""{StaticResource TextBrush}""
        FontFamily=""Segoe UI"" FontSize=""13"" UseLayoutRounding=""True"" TextOptions.TextFormattingMode=""Display"">
  <Grid>
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width=""236""/>
      <ColumnDefinition Width=""*""/>
    </Grid.ColumnDefinitions>
    <Border Background=""{StaticResource SideBg}"" BorderBrush=""{StaticResource LineBrush}"" BorderThickness=""0,0,1,0"">
      <DockPanel Margin=""12,20,12,14"">
        <StackPanel DockPanel.Dock=""Top"" Margin=""10,0,0,20"">
          <TextBlock Text=""Raintile"" FontSize=""21"" FontWeight=""SemiBold""/>
          <TextBlock x:Name=""Version"" Foreground=""{StaticResource DimBrush}"" FontSize=""12"" Margin=""0,2,0,0""/>
        </StackPanel>
        <StackPanel DockPanel.Dock=""Bottom"" Margin=""0,10,0,0"">
          <Border Height=""1"" Background=""{StaticResource LineBrush}"" Margin=""8,0,8,8""/>
          <ListBox x:Name=""NavBottom""/>
        </StackPanel>
        <ListBox x:Name=""Nav""/>
      </DockPanel>
    </Border>
    <Grid Grid.Column=""1"">
      <Grid.RowDefinitions>
        <RowDefinition Height=""Auto""/>
        <RowDefinition Height=""*""/>
        <RowDefinition Height=""Auto""/>
      </Grid.RowDefinitions>
      <StackPanel Margin=""36,24,36,14"">
        <TextBlock x:Name=""PageTitle"" FontSize=""24"" FontWeight=""SemiBold""/>
        <TextBlock x:Name=""PageDesc"" Foreground=""{StaticResource DimBrush}"" Margin=""0,5,0,0"" TextWrapping=""Wrap"" MaxWidth=""820"" HorizontalAlignment=""Left""/>
      </StackPanel>
      <Grid x:Name=""PageHost"" Grid.Row=""1""/>
      <Border Grid.Row=""2"" BorderBrush=""{StaticResource LineBrush}"" BorderThickness=""0,1,0,0"" Padding=""28,12"">
        <DockPanel>
          <StackPanel DockPanel.Dock=""Right"" Orientation=""Horizontal"">
            <Button x:Name=""BtnClose"" Content=""Close"" MinWidth=""90""/>
            <Button x:Name=""BtnSave"" Content=""Save and refresh"" Style=""{StaticResource AccentButton}"" Margin=""10,0,0,0""
                    ToolTip=""Ctrl+S""/>
          </StackPanel>
          <TextBlock x:Name=""Status"" VerticalAlignment=""Center"" Foreground=""{StaticResource DimBrush}""/>
        </DockPanel>
      </Border>
    </Grid>
    <!-- Shown after ""Save and refresh"" while the skin reloads -->
    <Grid x:Name=""Overlay"" Grid.ColumnSpan=""2"" Background=""#D915151B"" Visibility=""Collapsed"">
      <Border Style=""{StaticResource Card}"" Width=""400"" Padding=""28,24"" HorizontalAlignment=""Center"" VerticalAlignment=""Center"">
        <StackPanel>
          <TextBlock Text=""Saving and refreshing"" FontSize=""17"" FontWeight=""SemiBold""/>
          <TextBlock Text=""The launcher opens in a moment."" Foreground=""{StaticResource DimBrush}"" Margin=""0,4,0,18""/>
          <DockPanel Margin=""0,0,0,8"">
            <TextBlock x:Name=""ProgressPercent"" DockPanel.Dock=""Right"" FontWeight=""SemiBold"" Foreground=""{StaticResource AccentBrush}""/>
            <TextBlock x:Name=""ProgressStage"" Foreground=""{StaticResource DimBrush}"" FontSize=""12.5""/>
          </DockPanel>
          <Border x:Name=""ProgressTrack"" Height=""10"" CornerRadius=""5"" Background=""{StaticResource FieldBg}"" ClipToBounds=""True"">
            <Border x:Name=""ProgressBar"" Width=""0"" HorizontalAlignment=""Left"" CornerRadius=""5"" Background=""{StaticResource AccentBrush}""/>
          </Border>
        </StackPanel>
      </Border>
    </Grid>
  </Grid>
</Window>";
    }
}
