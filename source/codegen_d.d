﻿module codegen_d;
import defs;
import util;

void gencode_d(OGLFunctionFamily[] functionFamilies, OGLEnumGroup[] enums, string filename, string modulename, bool isStatic, string containerStruct) {
	import std.conv : text;

	char[] ret;

	// For OpenGL 4.5 output from the "printers" is around 1mb,
	//  so 6mb is beyond anything we'll actually need.
	// But it'll increase speed enough that it is worth
	//  the actual work to get it in code.
	ret.reserve(1024 * 1024 * 6); // 1kb * 1mb * 6mb

	if (isStatic) {
		// seriously what do you expect me to do with this?
		containerStruct = null;
	}

	string prefixContainer, prefix, prefixComment;
	if (containerStruct !is null) {
		if (isStatic) {
			prefixContainer = "    ";
			prefix = "        ";
		} else {
			prefixContainer = "";
			prefix = "    ";
		}
	} else {
		prefixContainer = "";
		prefix = "    ";
	}

	prefixComment = prefix ~ " + ";

	if (modulename !is null) {
		ret ~= "
/**
 * This is a set of OpenGL bindings.
 *
 * Generated by ./ogl_gen ....
 * Do not modify. Regenerate if changes are required.
 *
 * Macros:
 *    D_CODE = <pre><code class=\"D\">$0</code></pre>
 */\n"[1 .. $];

		ret ~= "module ";
		ret ~= modulename;
		ret ~= ";\n";
	} else {
			ret ~= "
/**
 * Macros:
 *    D_CODE = <pre><code class=\"D\">$0</code></pre>
 */\n"[1 .. $];
	}

	ret ~= import("D.d").removeUnicodeBOM;
	ret ~= "\n";

	import std.algorithm;
	import std.range : array;

	foreach(e; enums
		.map!(a => a.enums)
		.joiner
		.array
		.sort!((a, b) => a.name < b.name)
		.uniq!((a, b) => a.name == b.name)) {
		if (e.value !is null) {
			ret ~= "///\nenum ";
			ret ~= e.name;
			ret ~= " = ";

			if (e.value.length > 2 && e.value[0 .. 2] != "0x")
				ret ~= "0x";
			ret ~= e.value;
			ret ~= ";\n";
		}
	}
	ret ~= "\n";

	if (containerStruct !is null) {
		ret ~= "/// Container for bindings\n";
		ret ~= "struct ";
		ret ~= containerStruct;
		ret ~= " {\n";
	}

	foreach(grp; enums) {
		if (grp.name.length > 0) {
			bool haveAnyValid;
			foreach(e; grp.enums) {
				if (e.value !is null) {
					haveAnyValid = true;
				}
			}
			if (!haveAnyValid)
				continue;

			ret ~= prefixContainer;
			ret ~= "\t///\n\t";
			
			if (grp.isBitmask) {
				ret ~= prefixContainer;
				ret ~= "@Bitmaskable\n\t";
			}
			
			ret ~= prefixContainer;
			ret ~= "enum ";
			ret ~= grp.name;
			ret ~= " {\n";
			
			size_t i;
			foreach(e; grp.enums) {
				if (e.value !is null) {
					if (i > 0)
						ret ~= ",\n";
					
					ret ~= prefix;
					ret ~= "\t///\n\t";
					
					ret ~= prefix;
					if (e.name.length > 3 && e.name[0 .. 3] == "GL_") {
						ret ~= e.name[3 .. $].makeValidCIdentifier;
					} else {
						ret ~= e.name;
					}
					
					ret ~= " = ";
					if (e.value.length > 2 && e.value[0 .. 2] != "0x")
						ret ~= "0x";
					
					ret ~= e.value;
					i++;
				}
			}

			ret ~= "\n\t";
			ret ~= prefixContainer;
			ret ~= "}\n\n";
		}
	}

	if (isStatic) {
		ret ~= prefixContainer;
		ret ~= "extern(C) {\n";
	}

	foreach(k, family; functionFamilies) {
		foreach(i, func; family.functions) {
			if (i == 0) {
				ret ~= "\n";

				ret ~= prefix;
				ret ~= "/++\n";

				ret.genDDOC(family, prefixComment);

				ret ~= prefix;
				ret ~= " +/\n";
			} else {
				ret ~= prefix;
				ret ~= "/// Ditto\n";
			}

			OGLIntroducedIn introducedIn = family.introducedIn;
			if (func.introducedIn != OGLIntroducedIn.Unknown)
				introducedIn = func.introducedIn;

			if (introducedIn != OGLIntroducedIn.Unknown) {
				ret ~= prefix;
				ret ~= "@OpenGL_Version(OGLIntroducedIn.";
				ret ~= introducedIn.text;
				ret ~= ")\n";
			} else {
				ret ~= prefix;
				ret ~= "@OpenGL_Version(OGLIntroducedIn.Unknown)\n";
			}

			if (func.introducedInExtension !is null) {
				ret ~= prefix;
				ret ~= "@OpenGL_Extension(\"";
				ret ~= func.introducedInExtension;
				ret ~= "\")\n";
			}

			ret ~= prefix;

			if (!isStatic) {
				ret ~= "extern(C) ";
			}

			ret ~= func.returnType;

			if (isStatic) {
				ret ~= " ";
				ret ~= func.name;
				ret ~= "(";
			} else {
				ret ~= " function(";
			}

			if (func.argNames.length == 1 && func.argTypes[0] == "void") {
			} else {
				foreach(j, arg; func.argNames) {
					if (j > 0)
						ret ~= ", ";

					ret ~= func.argTypes[j];
					if (arg !is null) {
						ret ~= " ";

						switch(arg) {
							case "ref":
								ret ~= "ref_";
								break;
							case "in":
								ret ~= "in_";
								break;
							case "out":
								ret ~= "out_";
								break;
							default:
								ret ~= arg;
						}
					}
				}
			}

			if (isStatic) {
				ret ~= ") @system @nogc nothrow;\n";
			} else {
				ret ~= ") @system @nogc nothrow ";
				ret ~= func.name;
				ret ~= ";\n";
			}
		}
	}

	if (isStatic) {
		ret ~= prefixContainer;
		ret ~= "}\n";
	}

	if (containerStruct !is null) {
		ret ~= "}\n";
	}
	
	import std.file : write;
	write(filename, ret);
}

void genDDOC(T)(ref T ret, OGLFunctionFamily family, string prefix) {
	string prefix2 = prefix ~ "    ";
	string prefix3 = prefix ~ "                    ";

	ret ~= prefix;
	ret ~= family.familyOfFunction;
	ret ~= ": ";
	ret ~= family.fromFilename;
	ret ~= "\n";
	ret ~= prefix;
	ret ~= "\n";
	
	ret ~= prefix;
	ret.genDDOC(family.familyOfFunction, family.docs_description, prefix, prefix);
	if (ret[$ - 1] != '\n')
		ret ~= "\n";
	ret ~= prefix;
	ret ~= "\n";
	
	if (family.docs_notes.value_children.length > 0) {
		ret ~= prefix;
		ret.genDDOC(family.familyOfFunction, family.docs_notes, prefix, prefix);
		if (ret[$ - 1] != '\n')
			ret ~= "\n";
		ret ~= prefix;
		ret ~= "\n";
	}
	
	if (ret.length >= prefix.length * 2 + 2
			&& ret[$ - prefix.length - 1 .. $ - 1] == prefix
			&& ret[$ - prefix.length * 2 - 2 .. $ - prefix.length - 2] == prefix)
		// 2 empty lines here already, no need for another one
		ret.length--;
	else
		ret ~= prefix;
	ret ~= "Params:\n";

	size_t longestParam = 0;
	foreach(ref param; family.docs_parameters) {
		size_t length = 1;
		foreach(i, name; param.appliesToNames) {
			if (i > 0) {
				length += ", ".length;
			}

			if (name == "ref")
				length += "ref_".length;
			else
				length += name.length;
		}
		if (length > longestParam)
			longestParam = length;
	}

	foreach(ref param; family.docs_parameters) {
		ret ~= prefix2;

		size_t length = 0;
		foreach(i, name; param.appliesToNames) {
			if (i > 0) {
				ret ~= ", ";
				length += ", ".length;
			}

			if (name == "ref") {
				ret ~= "ref_";
				length += "ref_".length;
			} else {
				ret ~= name;
				length += name.length;
			}
		}

		for (size_t i = 0; i < longestParam - length; i++)
			ret ~= ' ';
		ret ~= "= ";
		ret.genDDOC(family.familyOfFunction, param.documentation, "", prefix3);
		if (ret[$ - 1] != '\n')
			ret ~= "\n";
	}

	ret ~= prefix;
	ret ~= "\n";

	ret ~= prefix;
	ret ~= "Copyright:\n";
	ret ~= prefix2;
	ret.genDDOC(family.familyOfFunction, family.docs_copyright, prefix2, prefix2);
	if (ret[$ - 1] != '\n')
		ret ~= "\n";
	ret ~= prefix;
	ret ~= "\n";

	ret ~= prefix;
	ret ~= "See_Also:\n";
	ret ~= prefix2;
	ret.genDDOC(family.familyOfFunction, family.docs_seealso, prefix2, prefix2);
	if (ret[$ - 1] != '\n')
		ret ~= "\n";
}

void genDDOC(T)(ref T ret, string functionFamily, ref OGLDocumentation ctx, string linetabs, string linetabsNext) {
	bool firstText=true;
	genDDOC(ret, functionFamily, ctx, linetabs, linetabsNext, firstText);
}

void genDDOC(T)(ref T ret, string functionFamily, ref OGLDocumentation ctx, string linetabs, string linetabsNext, ref bool firstText, bool inCode = false) {
	import std.string : splitLines, strip, stripRight, KeepTerminator;
	import std.algorithm : canFind;
	with(ctx) {
		string suffix;
		string macroPrefix, htmlTag;
		bool startCodeBlock = false;
		
		switch(type) {
			case OGLDocumentationType.LookupParameter:
				macroPrefix = "D_INLINECODE";
				goto case OGLDocumentationType.Container;
			case OGLDocumentationType.LookupConstant:
				macroPrefix = "D_INLINECODE";
				goto case OGLDocumentationType.Container;
			case OGLDocumentationType.LookupFunction:
				macroPrefix = "D_INLINECODE";
				goto case OGLDocumentationType.Container;
			case OGLDocumentationType.Title:
				htmlTag = "h3";
				goto case OGLDocumentationType.Container;
				
			case OGLDocumentationType.TableContainer:
				import std.conv : text;
				suffix = "table>[cols=" ~ value_numcols.text ~ "]";
				goto case OGLDocumentationType.Container;
			case OGLDocumentationType.TableHeader:
				suffix = "head";
				goto case OGLDocumentationType.Container;
			case OGLDocumentationType.TableBody:
				suffix = "body";
				goto case OGLDocumentationType.Container;
			case OGLDocumentationType.TableRow:
				suffix = "row";
				goto case OGLDocumentationType.Container;
			case OGLDocumentationType.TableEntry:
				suffix = "entry";
				goto case OGLDocumentationType.Container;
			case OGLDocumentationType.Copyright:
				ret ~= "&copy;";
				return;
			case OGLDocumentationType.Trademark:
				ret ~= "&trade;";
				return;
			case OGLDocumentationType.StyleContainer:
				if (value_string == "bold") {
					macroPrefix = "B";
				}
				goto case OGLDocumentationType.Container;
			case OGLDocumentationType.StyleCode:
				macroPrefix = "D_CODE";
				foreach(child; value_children) {
					// only start blocks for multiline code
					startCodeBlock = startCodeBlock || child.value_string.canFind('\n');
				}
				if (!startCodeBlock)
					macroPrefix = "D_INLINECODE";
				goto case OGLDocumentationType.Container;
			case OGLDocumentationType.Footnote:
				suffix = "\\/footnote";
				goto case OGLDocumentationType.Container;
			case OGLDocumentationType.InlineEquation:
				suffix = "|<equation";
				goto case OGLDocumentationType.Container;
				
			case OGLDocumentationType.MathMLContainer:
				suffix = "MathML[_]";
				goto case OGLDocumentationType.Container;
			case OGLDocumentationType.MathML_MI:
				suffix = "MathML:mi";
				goto case OGLDocumentationType.Container;
			case OGLDocumentationType.MathML_mn:
				suffix = "MathML:mn";
				goto case OGLDocumentationType.Container;
			case OGLDocumentationType.MathML_mrow:
				suffix = "MathML:mrow";
				goto case OGLDocumentationType.Container;
			case OGLDocumentationType.MathML_msup:
				suffix = "MathML:msup";
				goto case OGLDocumentationType.Container;
			case OGLDocumentationType.MathML_mo:
				suffix = "MathML:mo";
				goto case OGLDocumentationType.Container;
			case OGLDocumentationType.MathML_msub:
				suffix = "MathML:msub";
				goto case OGLDocumentationType.Container;
			case OGLDocumentationType.MathML_mfrac:
				suffix = "MathML:mfrac";
				goto case OGLDocumentationType.Container;
			case OGLDocumentationType.MathML_mtable:
				suffix = "MathML:mtable[" ~ value_string ~ "]";
				goto case OGLDocumentationType.Container;
			case OGLDocumentationType.MathML_mtr:
				suffix = "MathML:mtr";
				goto case OGLDocumentationType.Container;
			case OGLDocumentationType.MathML_mtd:
				suffix = "MathML:mtd[" ~ value_string ~ "]";
				goto case OGLDocumentationType.Container;
			case OGLDocumentationType.MathML_mspace:
				suffix = "MathML:mspace[ " ~ value_string ~ " ]";
				goto case OGLDocumentationType.Container;
			case OGLDocumentationType.MathML_mtext:
				suffix = "MathML:mtext[ " ~ value_string ~ " ]";
				goto case OGLDocumentationType.Container;
			case OGLDocumentationType.MathML_apply:
				suffix = "MathML:apply[ " ~ value_string ~ " ]";
				goto case OGLDocumentationType.Container;
			case OGLDocumentationType.MathML_mover:
				suffix = "MathML:mover";
				goto case OGLDocumentationType.Container;
			case OGLDocumentationType.MathML_munderover:
				suffix = "MathML:munderover";
				goto case OGLDocumentationType.Container;
			case OGLDocumentationType.MathML_msqrt:
				suffix = "MathML:msqrt";
				goto case OGLDocumentationType.Container;

			case OGLDocumentationType.IndexList:
				macroPrefix = "OL";
				goto case OGLDocumentationType.Container;
			case OGLDocumentationType.IndexItem:
				macroPrefix = "LI";
				goto case OGLDocumentationType.Container;
				
			case OGLDocumentationType.Link:
				macroPrefix = "LINK2 " ~ value_string ~ ",";
				goto case OGLDocumentationType.Container;
			case OGLDocumentationType.StyleSuperScript:
				htmlTag = "sup";
				goto case OGLDocumentationType.Container;
			case OGLDocumentationType.StyleSubScript:
				htmlTag = "sub";
				goto case OGLDocumentationType.Container;
				
			case OGLDocumentationType.Paragraph:
				goto case OGLDocumentationType.Container;
				
			case OGLDocumentationType.Container:
				if (startCodeBlock && ret.length >= 1 && ret[$ - 1] != '\n')
					ret ~= "\n" ~ linetabs ~ "\n" ~ linetabs;

				size_t preMacroPos = -1;
				if (startCodeBlock) {
					ret ~= "---\n" ~ linetabs;
				} else if (macroPrefix !is null) {
					preMacroPos = ret.length;
					ret ~= "$(";
					ret ~= macroPrefix;
					ret ~= " ";
				} else if (htmlTag !is null) {
					ret ~= "<";
					ret ~= htmlTag;
					ret ~= ">";
				}
				
				size_t codePos = ret.length;
				foreach(i, child; value_children)
					ret.genDDOC(functionFamily, child, linetabs, linetabsNext, firstText, startCodeBlock);
				if (codePos < ret.length && ret[codePos] == ' ' && preMacroPos != -1) {
					// space inside macro, remove space and place it before macro
					for (size_t i = codePos - 1; i >= preMacroPos; i--)
						ret[i] = ret[i - 1];
					ret[preMacroPos] = ' ';
				}
				
				if (startCodeBlock) {
					if (ret.length >= linetabs.length && ret[$ - linetabs.length .. $] == linetabs)
						ret ~= "---\n" ~ linetabs;
					else {
						if (ret.length && ret[$ - 1] != '\n')
							ret ~= '\n' ~ linetabs;
						ret ~= "---\n" ~ linetabs;
					}
				} else if (macroPrefix !is null) {
					if (macroPrefix == "D_INLINECODE" && ret.length && ret[$ - 1] == '\n')
						ret[$ - 1] = ')';
					else
						ret ~= ")";
				} else if (htmlTag !is null) {
					ret ~= "</";
					ret ~= htmlTag;
					ret ~= ">";
				}
				return;
				
			case OGLDocumentationType.Text:
				if (inCode) {
					foreach(line; value_string.splitLines(KeepTerminator.yes)) {
						if (line.length >= 4 && line[0 .. 4] == "    ")
							ret ~= line[4 .. $];
						else
							ret ~= line;
						firstText = false;
						if (ret.length > 0 && ret[$ - 1] == '\n')
							ret ~= linetabs;
					}
				} else {
					size_t i;
					string lines = value_string;
					
					string linesOld = lines;
					lines = lines
						.replace("NULL", "null")
						.replace("== null", "is null");
					
					foreach(line; lines.splitLines) {
						string lineStripped = line.strip;
						if (lineStripped.length > 0) {
							if (!firstText && !(line[0] == '.' || line[0] == ',' || line[0] == ';')) {
								ret ~= " ";
							}
							
							ret ~= lineStripped;
							i++;
							firstText = false;
							
							if (linesOld != lines) {
								ret ~= "\n" ~ linetabs;
							}
						}
					}
				}
				return;
			case OGLDocumentationType.MathML_mfenced:
				foreach(i, child; value_children)
					ret.genDDOC(functionFamily, child, linetabsNext, linetabsNext, firstText);
				return;
			case OGLDocumentationType.MathML_floor:
				ret ~= "<mml:floor/>";
				return;
			case OGLDocumentationType.MathML_infinity:
				ret ~= "&#8734;";
				return;
				
			case OGLDocumentationType.Unknown:
			default:
				// DO NOTHING!!!!!
				return;
				
		}
	}
}