using System;
using System.Globalization;
using System.Management.Automation.Host;
using System.Threading;

namespace ik.PowerShell;

internal class PS2EXEHost : PSHost
{
	private const bool CONSOLE = false;

	private PS2EXEApp parent;

	private PS2EXEHostUI ui;

	private CultureInfo originalCultureInfo = Thread.CurrentThread.CurrentCulture;

	private CultureInfo originalUICultureInfo = Thread.CurrentThread.CurrentUICulture;

	private Guid myId = Guid.NewGuid();

	public override CultureInfo CurrentCulture => originalCultureInfo;

	public override CultureInfo CurrentUICulture => originalUICultureInfo;

	public override Guid InstanceId => myId;

	public override string Name => "PS2EXE_Host";

	public override PSHostUserInterface UI => ui;

	public override Version Version => new Version(0, 2, 0, 0);

	public PS2EXEHost(PS2EXEApp app, PS2EXEHostUI ui)
	{
		parent = app;
		this.ui = ui;
	}

	public override void EnterNestedPrompt()
	{
	}

	public override void ExitNestedPrompt()
	{
	}

	public override void NotifyBeginApplication()
	{
	}

	public override void NotifyEndApplication()
	{
	}

	public override void SetShouldExit(int exitCode)
	{
		parent.ShouldExit = true;
		parent.ExitCode = exitCode;
	}
}
