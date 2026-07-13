using System;
using System.Management.Automation.Host;

namespace ik.PowerShell;

internal class PS2EXEHostRawUI : PSHostRawUserInterface
{
	private const bool CONSOLE = false;

	public override ConsoleColor BackgroundColor
	{
		get
		{
			return Console.BackgroundColor;
		}
		set
		{
			Console.BackgroundColor = value;
		}
	}

	public override Size BufferSize
	{
		get
		{
			return new Size(0, 0);
		}
		set
		{
			Console.BufferWidth = value.Width;
			Console.BufferHeight = value.Height;
		}
	}

	public override Coordinates CursorPosition
	{
		get
		{
			return new Coordinates(Console.CursorLeft, Console.CursorTop);
		}
		set
		{
			Console.CursorTop = value.Y;
			Console.CursorLeft = value.X;
		}
	}

	public override int CursorSize
	{
		get
		{
			return Console.CursorSize;
		}
		set
		{
			Console.CursorSize = value;
		}
	}

	public override ConsoleColor ForegroundColor
	{
		get
		{
			return Console.ForegroundColor;
		}
		set
		{
			Console.ForegroundColor = value;
		}
	}

	public override bool KeyAvailable
	{
		get
		{
			throw new Exception("Not implemented: ik.PowerShell.PS2EXEHostRawUI.KeyAvailable/Get");
		}
	}

	public override Size MaxPhysicalWindowSize => new Size(Console.LargestWindowWidth, Console.LargestWindowHeight);

	public override Size MaxWindowSize => new Size(Console.BufferWidth, Console.BufferWidth);

	public override Coordinates WindowPosition
	{
		get
		{
			return new Coordinates
			{
				X = Console.WindowLeft,
				Y = Console.WindowTop
			};
		}
		set
		{
			Console.WindowLeft = value.X;
			Console.WindowTop = value.Y;
		}
	}

	public override Size WindowSize
	{
		get
		{
			return new Size
			{
				Height = Console.WindowHeight,
				Width = Console.WindowWidth
			};
		}
		set
		{
			Console.WindowWidth = value.Width;
			Console.WindowHeight = value.Height;
		}
	}

	public override string WindowTitle
	{
		get
		{
			return Console.Title;
		}
		set
		{
			Console.Title = value;
		}
	}

	public override void FlushInputBuffer()
	{
		throw new Exception("Not implemented: ik.PowerShell.PS2EXEHostRawUI.FlushInputBuffer");
	}

	public override BufferCell[,] GetBufferContents(Rectangle rectangle)
	{
		throw new Exception("Not implemented: ik.PowerShell.PS2EXEHostRawUI.GetBufferContents");
	}

	public override KeyInfo ReadKey(ReadKeyOptions options)
	{
		ReadKeyForm readKeyForm = new ReadKeyForm();
		readKeyForm.ShowDialog();
		return readKeyForm.key;
	}

	public override void ScrollBufferContents(Rectangle source, Coordinates destination, Rectangle clip, BufferCell fill)
	{
		throw new Exception("Not implemented: ik.PowerShell.PS2EXEHostRawUI.ScrollBufferContents");
	}

	public override void SetBufferContents(Rectangle rectangle, BufferCell fill)
	{
		throw new Exception("Not implemented: ik.PowerShell.PS2EXEHostRawUI.SetBufferContents(1)");
	}

	public override void SetBufferContents(Coordinates origin, BufferCell[,] contents)
	{
		throw new Exception("Not implemented: ik.PowerShell.PS2EXEHostRawUI.SetBufferContents(2)");
	}
}
