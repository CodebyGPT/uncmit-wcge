using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;
using System.Management.Automation.Host;
using System.Security;

namespace ik.PowerShell;

internal class PS2EXEHostUI : PSHostUserInterface
{
	private const bool CONSOLE = false;

	private PS2EXEHostRawUI rawUI;

	public override PSHostRawUserInterface RawUI => rawUI;

	public PS2EXEHostUI()
	{
		rawUI = new PS2EXEHostRawUI();
	}

	public override Dictionary<string, PSObject> Prompt(string caption, string message, Collection<FieldDescription> descriptions)
	{
		return new Dictionary<string, PSObject>();
	}

	public override int PromptForChoice(string caption, string message, Collection<ChoiceDescription> choices, int defaultChoice)
	{
		return -1;
	}

	public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName, PSCredentialTypes allowedCredentialTypes, PSCredentialUIOptions options)
	{
		CredentialForm.UserPwd userPwd = CredentialForm.PromptForPassword(caption, message, targetName, userName, allowedCredentialTypes, options);
		if (userPwd != null)
		{
			SecureString secureString = new SecureString();
			char[] array = userPwd.Password.ToCharArray();
			foreach (char c in array)
			{
				secureString.AppendChar(c);
			}
			return new PSCredential(userPwd.User, secureString);
		}
		return null;
	}

	public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName)
	{
		CredentialForm.UserPwd userPwd = CredentialForm.PromptForPassword(caption, message, targetName, userName, PSCredentialTypes.Default, PSCredentialUIOptions.Default);
		if (userPwd != null)
		{
			SecureString secureString = new SecureString();
			char[] array = userPwd.Password.ToCharArray();
			foreach (char c in array)
			{
				secureString.AppendChar(c);
			}
			return new PSCredential(userPwd.User, secureString);
		}
		return null;
	}

	public override string ReadLine()
	{
		return Console.ReadLine();
	}

	public override SecureString ReadLineAsSecureString()
	{
		SecureString secureString = new SecureString();
		string text = Console.ReadLine();
		char[] array = text.ToCharArray();
		foreach (char c in array)
		{
			secureString.AppendChar(c);
		}
		return secureString;
	}

	public override void Write(ConsoleColor foregroundColor, ConsoleColor backgroundColor, string value)
	{
		Console.ForegroundColor = foregroundColor;
		Console.BackgroundColor = backgroundColor;
		Console.Write(value);
	}

	public override void Write(string value)
	{
		Console.ForegroundColor = ConsoleColor.White;
		Console.BackgroundColor = ConsoleColor.Black;
		Console.Write(value);
	}

	public override void WriteDebugLine(string message)
	{
		Console.ForegroundColor = ConsoleColor.DarkMagenta;
		Console.BackgroundColor = ConsoleColor.Black;
		Console.WriteLine(message);
	}

	public override void WriteErrorLine(string value)
	{
		Console.ForegroundColor = ConsoleColor.Red;
		Console.BackgroundColor = ConsoleColor.Black;
		Console.WriteLine(value);
	}

	public override void WriteLine(string value)
	{
		Console.ForegroundColor = ConsoleColor.White;
		Console.BackgroundColor = ConsoleColor.Black;
		Console.WriteLine(value);
	}

	public override void WriteProgress(long sourceId, ProgressRecord record)
	{
	}

	public override void WriteVerboseLine(string message)
	{
		Console.ForegroundColor = ConsoleColor.DarkCyan;
		Console.BackgroundColor = ConsoleColor.Black;
		Console.WriteLine(message);
	}

	public override void WriteWarningLine(string message)
	{
		Console.ForegroundColor = ConsoleColor.Yellow;
		Console.BackgroundColor = ConsoleColor.Black;
		Console.WriteLine(message);
	}
}
