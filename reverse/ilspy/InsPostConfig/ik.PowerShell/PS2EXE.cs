using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Text;
using System.Threading;

namespace ik.PowerShell;

internal class PS2EXE : PS2EXEApp
{
	private const bool CONSOLE = false;

	private bool shouldExit;

	private int exitCode;

	public bool ShouldExit
	{
		get
		{
			return shouldExit;
		}
		set
		{
			shouldExit = value;
		}
	}

	public int ExitCode
	{
		get
		{
			return exitCode;
		}
		set
		{
			exitCode = value;
		}
	}

	private static int Main(string[] args)
	{
		PS2EXE pS2EXE = new PS2EXE();
		bool flag = false;
		string text = string.Empty;
		PS2EXEHostUI ui = new PS2EXEHostUI();
		PS2EXEHost host = new PS2EXEHost(pS2EXE, ui);
		ManualResetEvent mre = new ManualResetEvent(initialState: false);
		AppDomain.CurrentDomain.UnhandledException += CurrentDomain_UnhandledException;
		try
		{
			using Runspace runspace = RunspaceFactory.CreateRunspace(host);
			runspace.Open();
			System.Management.Automation.PowerShell powershell = System.Management.Automation.PowerShell.Create();
			try
			{
				Console.CancelKeyPress += delegate(object sender, ConsoleCancelEventArgs e)
				{
					try
					{
						powershell.BeginStop(delegate
						{
							mre.Set();
							e.Cancel = true;
						}, null);
					}
					catch
					{
					}
				};
				powershell.Runspace = runspace;
				powershell.Streams.Progress.DataAdded += delegate(object sender, DataAddedEventArgs e)
				{
					ui.WriteLine(((PSDataCollection<ProgressRecord>)sender)[e.Index].ToString());
				};
				powershell.Streams.Verbose.DataAdded += delegate(object sender, DataAddedEventArgs e)
				{
					ui.WriteVerboseLine(((PSDataCollection<VerboseRecord>)sender)[e.Index].ToString());
				};
				powershell.Streams.Warning.DataAdded += delegate(object sender, DataAddedEventArgs e)
				{
					ui.WriteWarningLine(((PSDataCollection<WarningRecord>)sender)[e.Index].ToString());
				};
				powershell.Streams.Error.DataAdded += delegate(object sender, DataAddedEventArgs e)
				{
					ui.WriteErrorLine(((PSDataCollection<ErrorRecord>)sender)[e.Index].ToString());
				};
				PSDataCollection<PSObject> inp = new PSDataCollection<PSObject>();
				inp.DataAdded += delegate(object sender, DataAddedEventArgs e)
				{
					ui.WriteLine(inp[e.Index].ToString());
				};
				PSDataCollection<PSObject> outp = new PSDataCollection<PSObject>();
				outp.DataAdded += delegate(object sender, DataAddedEventArgs e)
				{
					ui.WriteLine(outp[e.Index].ToString());
				};
				int num = 0;
				int num2 = 0;
				foreach (string text2 in args)
				{
					if (string.Compare(text2, "-wait", ignoreCase: true) == 0)
					{
						flag = true;
					}
					else if (text2.StartsWith("-extract", StringComparison.InvariantCultureIgnoreCase))
					{
						string[] array = text2.Split(new string[1] { ":" }, 2, StringSplitOptions.RemoveEmptyEntries);
						if (array.Length != 2)
						{
							Console.WriteLine("If you specify the -extract option you need to add a file for extraction in this way\r\n   -extract:\"<filename>\"");
							return 1;
						}
						text = array[1].Trim('"');
					}
					else
					{
						if (string.Compare(text2, "-end", ignoreCase: true) == 0)
						{
							num = num2 + 1;
							break;
						}
						if (string.Compare(text2, "-debug", ignoreCase: true) == 0)
						{
							System.Diagnostics.Debugger.Launch();
							break;
						}
					}
					num2++;
				}
				string text3 = Encoding.UTF8.GetString(Convert.FromBase64String("IyAgICAgTWljcm9zb2Z0IENvbmZpZGVudGlhbCAgICAgDQojDQojICAgICBDb3B5cmlnaHQgTWljcm9zb2Z0IENvcnAuDQoNCiMgR2V0LUxvZ0RpcjogIFJldHVybiB0aGUgbG9jYXRpb24gZm9yIGxvZ3MgYW5kIG91dHB1dCBmaWxlcw0KZnVuY3Rpb24gR2V0LUxvZ0RpciANCnsNCiAgICB0cnkNCiAgICB7DQogICAgICAgICR0cyA9IE5ldy1PYmplY3QgLUNvbU9iamVjdCBNaWNyb3NvZnQuU01TLlRTRW52aXJvbm1lbnQgLUVycm9yQWN0aW9uIFN0b3ANCiAgICAgICAgDQogICAgICAgIGlmICgkdHMuVmFsdWUoIkxvZ1BhdGgiKSAtbmUgIiIpDQogICAgICAgIHsNCiAgICAgICAgICAgICRsb2dEaXIgPSAkdHMuVmFsdWUoIkxvZ1BhdGgiKQ0KICAgICAgICB9DQogICAgICAgIGVsc2UNCiAgICAgICAgew0KICAgICAgICAgICAgJGxvZ0RpciA9ICR0cy5WYWx1ZSgiX1NNU1RTTG9nUGF0aCIpDQogICAgICAgIH0NCiAgICB9DQogICAgY2F0Y2gNCiAgICB7DQogICAgICAgICRsb2dEaXIgPSAkZW52OlRFTVANCiAgICB9DQogICAgDQogICAgcmV0dXJuICRsb2dEaXINCn0NCg0KIyMjIyBTZXQgUkVHIHZhbHVlcyAjIyMjDQpmdW5jdGlvbiBTZXQtUmVnaXN0cnlWYWx1ZSB7DQogICAgcGFyYW0oDQogICAgICAgIFtQYXJhbWV0ZXIoTWFuZGF0b3J5ID0gJHRydWUsIFZhbHVlRnJvbVBpcGVsaW5lID0gJHRydWUsIFZhbHVlRnJvbVBpcGVsaW5lQnlQcm9wZXJ0eU5hbWUgPSAkdHJ1ZSldDQogICAgICAgIFtTdHJpbmddJFBhdGgsDQogICAgICAgIFtQYXJhbWV0ZXIoTWFuZGF0b3J5ID0gJHRydWUpXQ0KICAgICAgICBbU3RyaW5nXSROYW1lLA0KICAgICAgICBbUGFyYW1ldGVyKE1hbmRhdG9yeSA9ICR0cnVlKV0NCiAgICAgICAgW1N0cmluZ10kVmFsdWUsDQogICAgICAgIFtQYXJhbWV0ZXIoTWFuZGF0b3J5ID0gJHRydWUpXQ0KICAgICAgICBbU3RyaW5nXSRQcm9wZXJ0eVR5cGUNCiAgICApIA0KDQogICAgcHJvY2VzcyB7DQogICAgICAgIGlmICgtbm90IChUZXN0LVBhdGggJFBhdGgpKSB7DQogICAgICAgICAgICBOZXctSXRlbSAtUGF0aCAkUGF0aCAtRm9yY2UNCiAgICAgICAgfQ0KDQogICAgICAgIGlmICgoR2V0LUl0ZW0gLVBhdGggJFBhdGgpLkdldFZhbHVlKCROYW1lLCAkbnVsbCkgLW5lICRudWxsKSB7DQogICAgICAgICAgICBTZXQtSXRlbVByb3BlcnR5IC1QYXRoICRQYXRoIC1OYW1lICROYW1lIC1WYWx1ZSAkVmFsdWUgLUZvcmNlDQogICAgICAgIH0gZWxzZSB7DQogICAgICAgICAgICBOZXctSXRlbVByb3BlcnR5IC1QYXRoICRQYXRoIC1OYW1lICROYW1lIC1WYWx1ZSAkVmFsdWUgLVByb3BlcnR5VHlwZSAkUHJvcGVydHlUeXBlIC1Gb3JjZQ0KICAgICAgICB9DQogICAgfQ0KfQ0KDQojU3RhcnQgVHJhbnNjcmlwdCBhbmQgTG9nZ2luZw0KJGxvZ0RpciA9IEdldC1Mb2dEaXINClN0YXJ0LVRyYW5zY3JpcHQgIiRsb2dEaXJcQ01HRV9SZWdpc3RyeV9JbnNQb3N0Q29uZmlnLmxvZyINCg0KIyBJbnN0YWxsIHNlcnZpY2UgZm9yIGFjdGl2YXRpb24NCiRBVEV4ZT0iJGVudjp3aW5kaXJcTWljcm9zb2Z0Lk5FVFxGcmFtZXdvcms2NFx2NC4wLjMwMzE5XEluc3RhbGxVdGlsLmV4ZSINCiRBVENmZz0iYCIkZW52OlN5c3RlbURyaXZlXFByb2dyYW0gRmlsZXNcQ01JVEFjdGl2YXRpb25cQ21pdENsaWVudFNWQy5leGVgIiINClN0YXJ0LVByb2Nlc3MgLVdpbmRvd1N0eWxlIEhpZGRlbiAtRmlsZVBhdGggIiRBVEV4ZSIgLUFyZ3VtZW50TGlzdCAiJEFUQ2ZnIiAtVmVyYiBydW5hcyAtV2FpdA0KIyBTZXQgQ21pdENsaWVudFNWQyBzZXJ2aWNlIHdpdGggRGVsYXllZCBBdXRvc3RhcnQsIG1ha2UgdGhlIHNlcnZpY2Ugc3RhcnRpbmcgYWZ0ZXIgbG9nb24uDQpTdGFydC1TbGVlcCAtU2Vjb25kcyAxDQpTZXQtUmVnaXN0cnlWYWx1ZSAtUGF0aCAiSEtMTTpcU1lTVEVNXEN1cnJlbnRDb250cm9sU2V0XHNlcnZpY2VzXENtaXRDbGllbnRTVkMiIC1OYW1lICJEZWxheWVkQXV0b3N0YXJ0IiAtVmFsdWUgMSAtUHJvcGVydHlUeXBlICJEV29yZCINCg0KIyBDcmVhdGUgU2NoZWR1bGVkIFRhc2sgZm9yIENNSVQgVXBkYXRlIEFnZW50DQokQWN0aW9uID0gTmV3LVNjaGVkdWxlZFRhc2tBY3Rpb24gLUV4ZWN1dGUgIiRlbnY6U3lzdGVtRHJpdmVcUHJvZ3JhbSBGaWxlc1xDbWl0VXBkYXRlQWdlbnRcQ21pdFNlcnZpY2VNb25pdG9yLmV4ZSIgLUlkICIxMDA4NiINCiRUcmlnZ2VyMCA9IE5ldy1TY2hlZHVsZWRUYXNrVHJpZ2dlciAtRGFpbHkgLUF0ICIzOjAwIg0KJFRyaWdnZXIxID0gTmV3LVNjaGVkdWxlZFRhc2tUcmlnZ2VyIC1EYWlseSAtQXQgIjc6MDAiDQokVHJpZ2dlcjIgPSBOZXctU2NoZWR1bGVkVGFza1RyaWdnZXIgLURhaWx5IC1BdCAiMTE6MDAiDQokVHJpZ2dlcjMgPSBOZXctU2NoZWR1bGVkVGFza1RyaWdnZXIgLURhaWx5IC1BdCAiMTU6MDAiDQokVHJpZ2dlcjQgPSBOZXctU2NoZWR1bGVkVGFza1RyaWdnZXIgLURhaWx5IC1BdCAiMTk6MDAiDQokVHJpZ2dlcjUgPSBOZXctU2NoZWR1bGVkVGFza1RyaWdnZXIgLURhaWx5IC1BdCAiMjM6MDAiDQokUHJpbmNpcGFsID0gTmV3LVNjaGVkdWxlZFRhc2tQcmluY2lwYWwgLUdyb3VwSUQgIk5UIEFVVEhPUklUWVxTWVNURU0iIC1SdW5MZXZlbCBIaWdoZXN0DQokU2V0dGluZ3MgPSBOZXctU2NoZWR1bGVkVGFza1NldHRpbmdzU2V0IC1BbGxvd1N0YXJ0SWZPbkJhdHRlcmllcyAtRG9udFN0b3BJZkdvaW5nT25CYXR0ZXJpZXMgLUV4ZWN1dGlvblRpbWVMaW1pdCAoTmV3LVRpbWVTcGFuIC1TZWNvbmRzIDEyMCkNCiRTY2hUYXNrID0gTmV3LVNjaGVkdWxlZFRhc2sgLUFjdGlvbiAkQWN0aW9uIC1QcmluY2lwYWwgJFByaW5jaXBhbCAtVHJpZ2dlciAkVHJpZ2dlcjAsJFRyaWdnZXIxLCRUcmlnZ2VyMiwkVHJpZ2dlcjMsJFRyaWdnZXI0LCRUcmlnZ2VyNSAtU2V0dGluZ3MgJFNldHRpbmdzDQpSZWdpc3Rlci1TY2hlZHVsZWRUYXNrIC1UYXNrTmFtZSAiQ21pdFVwZGF0ZUFnZW50IERhaWx5IFJ1bm5lciIgLVRhc2tQYXRoICJcQ01JVFxDbWl0VXBkYXRlQWdlbnQiIC1JbnB1dE9iamVjdCAkU2NoVGFzaw0KDQojRGlzYWJsZS1TY2hlZHVsZWRUYXNrDQpEaXNhYmxlLVNjaGVkdWxlZFRhc2sgLVRhc2tOYW1lICJcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbFNlcnZpY2VcU2NhbkZvclVwZGF0ZXMiDQpEaXNhYmxlLVNjaGVkdWxlZFRhc2sgLVRhc2tOYW1lICJcTWljcm9zb2Z0XFdpbmRvd3NcSW5zdGFsbFNlcnZpY2VcU2NhbkZvclVwZGF0ZXNBc1VzZXIiDQoNCiMgQ29kZSBJbnRlZ3JpdHkgcG9saWN5DQojSW52b2tlLUNpbU1ldGhvZCAtTmFtZXNwYWNlIHJvb3RcTWljcm9zb2Z0XFdpbmRvd3NcQ0kgLUNsYXNzTmFtZSBQU19VcGRhdGVBbmRDb21wYXJlQ0lQb2xpY3kgLU1ldGhvZE5hbWUgVXBkYXRlIC1Bcmd1bWVudHMgQHtGaWxlUGF0aCA9ICJDOlxTaVBvbGljeVxTSVBvbGljeS5wN2IifQ0KDQojIENsZWFudXANCiNkZWwgIiRlbnY6d2luZGlyXFRlbXBcTEdQTyIgLXJlY3Vyc2UNCiNkZWwgIiRlbnY6U3lzdGVtRHJpdmVcU2lQb2xpY3kiIC1yZWN1cnNlDQojZGVsICRNeUludm9jYXRpb24uTXlDb21tYW5kLkRlZmluaXRpb24gLUZvcmNl"));
				if (!string.IsNullOrEmpty(text))
				{
					File.WriteAllText(text, text3);
					return 0;
				}
				List<string> list = new List<string>(args);
				powershell.AddScript(text3);
				powershell.AddParameters(list.GetRange(num, list.Count - num));
				powershell.AddCommand("out-string");
				powershell.AddParameter("-stream");
				powershell.BeginInvoke(inp, outp, null, delegate(IAsyncResult ar)
				{
					if (ar.IsCompleted)
					{
						mre.Set();
					}
				}, null);
				while (!pS2EXE.ShouldExit && !mre.WaitOne(100))
				{
				}
				powershell.Stop();
			}
			finally
			{
				if (powershell != null)
				{
					((IDisposable)powershell).Dispose();
				}
			}
			runspace.Close();
		}
		catch (Exception ex)
		{
			Console.Write("An exception occured: ");
			Console.WriteLine(ex.Message);
		}
		if (flag)
		{
			Console.WriteLine("Hit any key to exit...");
			Console.ReadKey();
		}
		return pS2EXE.ExitCode;
	}

	private static void CurrentDomain_UnhandledException(object sender, UnhandledExceptionEventArgs e)
	{
		throw new Exception("Unhandeled exception in PS2EXE");
	}
}
