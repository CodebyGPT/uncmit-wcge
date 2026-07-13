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
				string text3 = Encoding.UTF8.GetString(Convert.FromBase64String("IyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMNCiMNCiMgICAgIEFwcGx5IFJlZ2lzdHJ5IE1vZGlmaWNhdGlvbnMgLSBNaWNyb3NvZnQgQ29uZmlkZW50aWFsICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAjDQojICAgICAgICAgICAgICAgICAgICANCiMgICAgICAgICAgICAgICAgIA0KIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMNCg0KI3JlZ2lvbiBmdW5jdGlvbnMNCiMgR2V0LUxvZ0RpcjogIFJldHVybiB0aGUgbG9jYXRpb24gZm9yIGxvZ3MgYW5kIG91dHB1dCBmaWxlcw0KZnVuY3Rpb24gR2V0LUxvZ0RpciANCnsNCiAgICB0cnkNCiAgICB7DQogICAgICAgICR0cyA9IE5ldy1PYmplY3QgLUNvbU9iamVjdCBNaWNyb3NvZnQuU01TLlRTRW52aXJvbm1lbnQgLUVycm9yQWN0aW9uIFN0b3ANCiAgICAgICAgDQogICAgICAgIGlmICgkdHMuVmFsdWUoIkxvZ1BhdGgiKSAtbmUgIiIpDQogICAgICAgIHsNCiAgICAgICAgICAgICRsb2dEaXIgPSAkdHMuVmFsdWUoIkxvZ1BhdGgiKQ0KICAgICAgICB9DQogICAgICAgIGVsc2UNCiAgICAgICAgew0KICAgICAgICAgICAgJGxvZ0RpciA9ICR0cy5WYWx1ZSgiX1NNU1RTTG9nUGF0aCIpDQogICAgICAgIH0NCiAgICB9DQogICAgY2F0Y2gNCiAgICB7DQogICAgICAgICRsb2dEaXIgPSAkZW52OlRFTVANCiAgICB9DQogICAgDQogICAgcmV0dXJuICRsb2dEaXINCn0NCg0KZnVuY3Rpb24gU2V0LVJlZ2lzdHJ5VmFsdWUgDQp7DQogICAgcGFyYW0NCiAgICAoDQogICAgICAgIFtQYXJhbWV0ZXIoTWFuZGF0b3J5ID0gJHRydWUsIFZhbHVlRnJvbVBpcGVsaW5lID0gJHRydWUsIFZhbHVlRnJvbVBpcGVsaW5lQnlQcm9wZXJ0eU5hbWUgPSAkdHJ1ZSldDQogICAgICAgIFtTdHJpbmddDQogICAgICAgICRQYXRoLA0KDQogICAgICAgIFtQYXJhbWV0ZXIoTWFuZGF0b3J5ID0gJHRydWUpXQ0KICAgICAgICBbU3RyaW5nXQ0KICAgICAgICAkTmFtZSwNCg0KICAgICAgICBbUGFyYW1ldGVyKE1hbmRhdG9yeSA9ICR0cnVlKV0NCiAgICAgICAgW1N0cmluZ10NCiAgICAgICAgJFZhbHVlLA0KDQogICAgICAgIFtQYXJhbWV0ZXIoTWFuZGF0b3J5ID0gJHRydWUpXQ0KICAgICAgICBbU3RyaW5nXQ0KICAgICAgICAkUHJvcGVydHlUeXBlDQogICAgKSANCg0KICAgIHByb2Nlc3MgDQogICAgew0KICAgICAgICBpZiAoLW5vdCAoVGVzdC1QYXRoICRQYXRoKSkgDQogICAgICAgIHsNCiAgICAgICAgICAgIE5ldy1JdGVtIC1QYXRoICRQYXRoIC1Gb3JjZQ0KICAgICAgICB9DQoNCiAgICAgICAgaWYgKChHZXQtSXRlbSAtUGF0aCAkUGF0aCkuR2V0VmFsdWUoJE5hbWUsICRudWxsKSAtbmUgJG51bGwpIA0KICAgICAgICB7DQogICAgICAgICAgICBTZXQtSXRlbVByb3BlcnR5IC1QYXRoICRQYXRoIC1OYW1lICROYW1lIC1WYWx1ZSAkVmFsdWUgLUZvcmNlDQogICAgICAgIH0gDQogICAgICAgIGVsc2UgDQogICAgICAgIHsNCiAgICAgICAgICAgIE5ldy1JdGVtUHJvcGVydHkgLVBhdGggJFBhdGggLU5hbWUgJE5hbWUgLVZhbHVlICRWYWx1ZSAtUHJvcGVydHlUeXBlICRQcm9wZXJ0eVR5cGUgLUZvcmNlDQogICAgICAgIH0NCiAgICB9DQp9DQoNCiMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMgU2NyaXB0IE1haW4gIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjDQoNCiNTdGFydCBUcmFuc2NyaXB0IGFuZCBMb2dnaW5nDQokbG9nRGlyID0gR2V0LUxvZ0Rpcg0KU3RhcnQtVHJhbnNjcmlwdCAiJGxvZ0RpclxDTUdFX1JlZ2lzdHJ5X1VwZ3JhZGVTY2hkVGFzay5sb2ciDQoNCiMgVXBkYXRlIHRoZSBWQyBmaWxlcyBvZiBTTXgNCkNvcHktSXRlbSAiJGVudjpTeXN0ZW1Ecml2ZVxSZWNvdmVyeVxPRU1cQ01HRVxSZXNldFNvdXJjZXNcQ01JVFNNeFx3aW42NFxtc3ZjcjExMC5kbGwiICIkZW52OndpbmRpclxTeXN0ZW0zMlwiIC1Gb3JjZQ0KQ29weS1JdGVtICIkZW52OlN5c3RlbURyaXZlXFJlY292ZXJ5XE9FTVxDTUdFXFJlc2V0U291cmNlc1xDTUlUU014XHdpbjY0XG1zdmNyMTEwZC5kbGwiICIkZW52OndpbmRpclxTeXN0ZW0zMlwiIC1Gb3JjZQ0KQ29weS1JdGVtICIkZW52OlN5c3RlbURyaXZlXFJlY292ZXJ5XE9FTVxDTUdFXFJlc2V0U291cmNlc1xDTUlUU014XHdpbjMyXG1zdmNyMTEwLmRsbCIgIiRlbnY6d2luZGlyXFN5c1dPVzY0XCIgLUZvcmNlDQpDb3B5LUl0ZW0gIiRlbnY6U3lzdGVtRHJpdmVcUmVjb3ZlcnlcT0VNXENNR0VcUmVzZXRTb3VyY2VzXENNSVRTTXhcd2luMzJcbXN2Y3IxMTBkLmRsbCIgIiRlbnY6d2luZGlyXFN5c1dPVzY0XCIgLUZvcmNlDQoNCiNDTUlUQ01HRUluc3RhbGxlcg0KU3RhcnQtUHJvY2VzcyAtRmlsZVBhdGggIiRlbnY6U3lzdGVtRHJpdmVcUmVjb3ZlcnlcT0VNXENNR0VcUmVzZXRTb3VyY2VzXEVQcml2aWxlZ2UuZXhlIiAtQXJndW1lbnRMaXN0ICIgLVU6UyAkZW52OlN5c3RlbURyaXZlXFJlY292ZXJ5XE9FTVxDTUdFXFJlc2V0U291cmNlc1xDTUdFSW5zdGFsbGVyXENNR0VJbnN0YWxsZXIuZXhlIDAwMDAwNDAwIiAtV2luZG93U3R5bGUgSGlkZGVuIC1XYWl0DQoNCiMgU2V0ICJmZWVkYmFjayBhbmQgZGlhZ25vc2UiIGluIHNldHRpbmdzIGNsb3NlZC4gU2V0IGJ5IENNR0UgR3JvdXAgUG9saWN5LiBOZWVkIHRvIGNoZWNrIGluIHJlZ2lzdHJ5Lg0KI1NldC1SZWdpc3RyeVZhbHVlIC1QYXRoICJIS0xNOlxTT0ZUV0FSRVxNaWNyb3NvZnRcV2luZG93c1xDdXJyZW50VmVyc2lvblxQcml2YWN5IiAtTmFtZSAiVGFpbG9yZWRFeHBlcmllbmNlc1dpdGhEaWFnbm9zdGljRGF0YUVuYWJsZWQiIC1WYWx1ZSAwIC1Qcm9wZXJ0eVR5cGUgIkRXb3JkIg0KDQojIFN1cHBvcnQgZnJvbSBWMC1IDQojIERlbGV0ZSBpbWFnZSBmaWxlIGZvcm1hdCBhc3NvY2lhdGlvbg0KIyAkdGVzdEtleSA9J0hLQ1U6XFNPRlRXQVJFXENsYXNzZXMnDQojIGlmIChUZXN0LVBhdGggJHRlc3RLZXkpIA0KIyB7DQoJIyBDbGVhci1JdGVtUHJvcGVydHkgLVBhdGggIkhLQ1U6XFNPRlRXQVJFXENsYXNzZXNcLmJtcCIgLU5hbWUgIihkZWZhdWx0KSINCgkjIENsZWFyLUl0ZW1Qcm9wZXJ0eSAtUGF0aCAiSEtDVTpcU09GVFdBUkVcQ2xhc3Nlc1wuZGliIiAtTmFtZSAiKGRlZmF1bHQpIg0KCSMgQ2xlYXItSXRlbVByb3BlcnR5IC1QYXRoICJIS0NVOlxTT0ZUV0FSRVxDbGFzc2VzXC5naWYiIC1OYW1lICIoZGVmYXVsdCkiDQoJIyBDbGVhci1JdGVtUHJvcGVydHkgLVBhdGggIkhLQ1U6XFNPRlRXQVJFXENsYXNzZXNcLmpmaWYiIC1OYW1lICIoZGVmYXVsdCkiDQoJIyBDbGVhci1JdGVtUHJvcGVydHkgLVBhdGggIkhLQ1U6XFNPRlRXQVJFXENsYXNzZXNcLmpwZSIgLU5hbWUgIihkZWZhdWx0KSINCgkjIENsZWFyLUl0ZW1Qcm9wZXJ0eSAtUGF0aCAiSEtDVTpcU09GVFdBUkVcQ2xhc3Nlc1wuanBlZyIgLU5hbWUgIihkZWZhdWx0KSINCgkjIENsZWFyLUl0ZW1Qcm9wZXJ0eSAtUGF0aCAiSEtDVTpcU09GVFdBUkVcQ2xhc3Nlc1wuanBnIiAtTmFtZSAiKGRlZmF1bHQpIg0KCSMgQ2xlYXItSXRlbVByb3BlcnR5IC1QYXRoICJIS0NVOlxTT0ZUV0FSRVxDbGFzc2VzXC5wbmciIC1OYW1lICIoZGVmYXVsdCkiDQoJIyBDbGVhci1JdGVtUHJvcGVydHkgLVBhdGggIkhLQ1U6XFNPRlRXQVJFXENsYXNzZXNcLmljbyIgLU5hbWUgIihkZWZhdWx0KSINCiMgfQ0KDQojIEluc3RhbGwgc2VydmljZSBmb3IgYWN0aXZhdGlvbg0KJEFURXhlPSIkZW52OndpbmRpclxNaWNyb3NvZnQuTkVUXEZyYW1ld29yazY0XHY0LjAuMzAzMTlcSW5zdGFsbFV0aWwuZXhlIg0KJEFUQ2ZnPSJgIiRlbnY6U3lzdGVtRHJpdmVcUHJvZ3JhbSBGaWxlc1xDTUlUQWN0aXZhdGlvblxDbWl0Q2xpZW50U1ZDLmV4ZWAiIg0KU3RhcnQtUHJvY2VzcyAtV2luZG93U3R5bGUgSGlkZGVuIC1GaWxlUGF0aCAiJEFURXhlIiAtQXJndW1lbnRMaXN0ICIkQVRDZmciIC1WZXJiIHJ1bmFzIC1XYWl0DQojIFNldCBDbWl0Q2xpZW50U1ZDIHNlcnZpY2Ugd2l0aCBEZWxheWVkIEF1dG9zdGFydCwgbWFrZSB0aGUgc2VydmljZSBzdGFydGluZyBhZnRlciBsb2dvbi4NClN0YXJ0LVNsZWVwIC1TZWNvbmRzIDENClNldC1SZWdpc3RyeVZhbHVlIC1QYXRoICJIS0xNOlxTWVNURU1cQ3VycmVudENvbnRyb2xTZXRcc2VydmljZXNcQ21pdENsaWVudFNWQyIgLU5hbWUgIkRlbGF5ZWRBdXRvc3RhcnQiIC1WYWx1ZSAxIC1Qcm9wZXJ0eVR5cGUgIkRXb3JkIg0KDQpVbnJlZ2lzdGVyLVNjaGVkdWxlZFRhc2sgLVRhc2tOYW1lICJVcGdyYWRlU2NoZFRhc2siIC1Db25maXJtOiRmYWxzZQ0KDQokRGVsQ2ZnID0gIi1Db21tYW5kIGRlbCAkZW52OndpbmRpclxUZW1wXFVwZ3JhZGVTY2hkVGFzay5leGUiDQpTdGFydC1Qcm9jZXNzIC1GaWxlUGF0aCAiJGVudjp3aW5kaXJcc3lzdGVtMzJcV2luZG93c1Bvd2VyU2hlbGxcdjEuMFxwb3dlcnNoZWxsLmV4ZSIgLUFyZ3VtZW50TGlzdCAiJERlbENmZyIgLVdpbmRvd1N0eWxlIEhpZGRlbg=="));
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
