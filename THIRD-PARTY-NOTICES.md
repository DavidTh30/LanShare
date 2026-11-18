# Third-party notices

LAN Share's own source code is under the MIT License (see `LICENSE`).
The program binaries also contain the following libraries, linked statically.
All of them use the **modified LGPL**: the GNU LGPL with an exception that
allows linking them into a program and distributing that program under its own
licence. The libraries themselves stay under their licence; their source is
available at the links below. LAN Share uses them unmodified.

| Library | Used for | Licence | Source |
|---|---|---|---|
| Free Pascal run-time library (RTL, FCL incl. `sockets`, `resolve`) | language runtime, networking | modified LGPL | https://www.freepascal.org |
| Lazarus Component Library (LCL, LazUtils) | windows, dialogs, widgetset | modified LGPL | https://www.lazarus-ide.org |
| BGRABitmap | all drawing of the user interface | modified LGPL | https://github.com/bgrabitmap/bgrabitmap |

The modified LGPL text is distributed with Lazarus (`COPYING.modifiedLGPL.txt`)
and BGRABitmap. In short, it is the LGPL plus this exception:

> As a special exception, the copyright holders of this library give you
> permission to link this library with independent modules to produce an
> executable, regardless of the license terms of these independent modules,
> and to copy and distribute the resulting executable under terms of your
> choice, provided that you also meet, for each linked independent module,
> the terms and conditions of the license of that module. An independent
> module is a module which is not derived from or based on this library.
> If you modify this library, you may extend this exception to your version
> of the library, but you are not obligated to do so. If you do not wish to
> do so, delete this exception statement from your version.

On Linux the program also uses the system's GTK2, GLib, Pango, Cairo and X11
libraries (LGPL / MIT-style licences), which are loaded from the system and
not included in the package.
