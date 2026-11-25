module argparse;

import std::io;
import std::os;
import std::core::string;
import std::core::log;
import std::collections::map;
import std::collections::list;
import std::collections::object;
import std::sort;

struct Flag_Slot (Printable)
{
  any value;
  String name;
  String description;
  struct loc {
    String file;
    int line;
  }
  int order;
  bool is_required;
  bool is_default;

} 

fn bool Flag_Slot.is_equal(&self, Flag_Slot another) @operator(==)
{
  return self.name == another.name;
}

struct Flag_context (Printable)
{
  HashMap{String, Flag_Slot} slots;

  String program_name;
  String[] rest_args;
  List{Flag_Slot} required_args;
  Flag_Slot* default_arg;
}

fn long? Flag_context.to_format(&self, Formatter *f) @dynamic => io::struct_to_format(*self, f, false);
fn long? Flag_Slot.to_format(&self, Formatter *f) @dynamic => io::struct_to_format(*self, f, false);

Flag_context default_flag_context;

<*
 @require name != "h"     : "-h is preserved for automatic help"
 @require name != "-help" : "-h is preserved for automatic help"
*>
macro void @flag(#arg, String name, String description, String file = $$FILEPATH, int line = $$LINE, Flag_context* flag_context = &default_flag_context, bool is_required = false, bool is_default = false)
{
  $switch $Typeof(#arg):
    $case int:
    $case float:
    $case String:
      {}
    $case bool:
    if (is_default){
      log::error(string::tformat("%s:%d argument `%s` is a bool, which can't be a default argument", file, line, name));
      os::exit(-1);
    }
    $default:
    log::error(string::tformat("%s:%d type of varaible %s - %s not supported", file, line, name, $Typeof(#arg)));
    os::exit(-1);
  $endswitch

  flag{$Typeof(#arg)}(&#arg, name, description, file, line, flag_context, is_required, is_default);
}

fn void flag(Type* arg, String name, String description, String file, int line, Flag_context* flag_context = &default_flag_context, bool is_required, bool is_default) <Type>
{
  Flag_Slot? existing_slot = flag_context.slots.get(name);

  if (try unwrapped_existing_slot = existing_slot) {
    log::error(string::tformat("%s:%d Redifiniton of \"%s\"", file, line, name));
    log::error(string::tformat("Previous definition %s:%d", unwrapped_existing_slot.loc.file, unwrapped_existing_slot.loc.line));
    os::exit(-1);
  }

  if (flag_context.default_arg != null && is_default) {
    log::error(string::tformat("%s:%d Only one argument can be default", file, line));
    log::error(string::tformat("Previous definition: %s:%d", flag_context.default_arg.loc.file, flag_context.default_arg.loc.line));
    os::exit(-1);
  }

  int order = (int)flag_context.slots.len();
  if (is_default) order = -1;

  Flag_Slot new_slot = {
    .value = arg,
    .name = name,
    .description = description,
    .loc = {
      .file = file,
      .line = line,
    },
    .order = order,
    .is_required = is_required || is_default,
    .is_default = is_default
  };

  flag_context.slots.set(name, new_slot);

  if (is_required || is_default){
    flag_context.required_args.push(new_slot);
  }

  if (is_default){
    flag_context.default_arg = flag_context.slots.get_ref(name)!!;
  }
}

faultdef MALFORMED_FLAG, FLAG_TYPE_NOT_SUPPORTED, MISSING_ARGUMENT, NONEXISTENT_FLAG;

fn void? flag_parse(String[] args, Flag_context* flag_context = &default_flag_context)
{
  flag_context.program_name = args[0];
  flag_context.rest_args = args[1..];

  if (flag_context.rest_args.len == 0 || flag_context.rest_args[0] == "-h" || flag_context.rest_args[0] == "--help"){
    DString sb = dstring::temp();
    flag_print_options(&sb);
    io::printn(sb);
    return;
  }

  String first_arg = flag_context.rest_args[0];

  // default_arg handling
  if (flag_context.default_arg != null){
    if (first_arg.trim().starts_with("-")){
      log::error("The `%s` default argument is missing", flag_context.required_args[0].name);

      return MISSING_ARGUMENT~;
    }

    Flag_Slot*? slot = flag_context.slots.get_ref(flag_context.default_arg.name);
    set_slot_value(flag_context, slot, flag_context.default_arg.name, first_arg)!;

    sz ok = flag_context.required_args.remove_item(*slot)!;
    always_assert(ok<2, "Duplicate elements present in Flag_context");

    flag_context.rest_args = flag_context.rest_args[1..];
  }

  // TODO: make required arguments work using HashMap

  while (!(flag_context.rest_args.len == 0)) {
    if (flag_context.rest_args[0] == "--") break;

    String name = flag_context.rest_args[0];

    bool ignore = false;

    if (name.starts_with("/")) {
      name = name.strip_prefix("/");
      ignore = true;
    }

    // TODO: Add support for --
    if (!name.trim().starts_with("-")) {
      log::error("\"%s\" malformed flag. All flags start with \"-\"", name);
      return MALFORMED_FLAG~;
    }

    name = name.strip_prefix("-");

    Flag_Slot*? slot = flag_context.slots.get_ref(name);
    if (catch excuse = slot) {
      log::error("No such flag exists");
      return NONEXISTENT_FLAG~;
    }

    if(slot.is_required){
      sz ok = flag_context.required_args.remove_item(*slot);
      always_assert(ok<2, "Duplicate elements present in Flag_context");
    }

    String type_name;
    switch(slot.value.type){
      case bool:
        // TODO: also make user be able to provide argument
        if (!ignore) *(bool*)slot.value.ptr = true;
        flag_context.rest_args = flag_context.rest_args[1..];
      case int:
        type_name = "int";
        nextcase default;
      case float:
        type_name = "float";
        nextcase default;
      case String:
        type_name = "string";
        nextcase default;
      default:
        if (flag_context.rest_args.len == 1) {
          log::error("No %s value is provided for flag \"-%s\"", type_name, name);
          return MISSING_ARGUMENT~;
        }
        set_slot_value(flag_context, slot, flag_context.rest_args[0], flag_context.rest_args[1], ignore)!;
        flag_context.rest_args = flag_context.rest_args[2..];
    }
  }

  if (flag_context.required_args.len() > 0) {
    io::print("The following arguments are required: ");

    foreach (i, required_arg : flag_context.required_args) {
      io::printf("%s%s", required_arg.name,
          i < flag_context.required_args.len() - 1 ? ", " : "");
    }

    io::printn("");
    return MISSING_ARGUMENT~;
  }
}

fn void? set_slot_value(Flag_context* flag_context, Flag_Slot* slot, String name, String value, bool ignore = false)
{
  switch(slot.value.type) {
    // TODO: Add all types of int
    case int: 
      int? int_value = value.to_int();
      if (catch excuse = int_value) {
        log::error("-%s: \"%s\" is not a valid integer", name, value);
        return string::MALFORMED_INTEGER~;
      }
      if (!ignore) *(int*)slot.value.ptr = int_value;
    case float: 
      float? float_value = value.to_float();
      if (catch excuse = float_value) {
        log::error("-%s: \"%s\" is not a valid integer", name, value);
        return string::MALFORMED_FLOAT~;
      }

      if (!ignore) *(float*)slot.value.ptr = float_value;
    case String:
      String string_value = value;
      if (!ignore) *(String*)slot.value.ptr = string_value;
    default: unreachable("flag_parse: unreachable");
  }
}



fn void flag_print_options(DString* builder, Flag_context* flag_context = &default_flag_context){
  @pool(){
      List{Flag_Slot} sorted_slots;

      sorted_slots.init(tmem);
      flag_context.slots.@each_entry(;slot){
        sorted_slots.push(slot.value);
      };

      quicksort(&sorted_slots, fn int (Flag_Slot* a, Flag_Slot *b) { return (a.order < b.order) ? -1 : 1; });

      builder.appendfn("Usage: %s [OPTIONS]", argparse::default_flag_context.program_name);
      builder.appendfn("OPTIONS:");
      foreach (slot : sorted_slots){
        switch(slot.value.type){
          case bool:   builder.appendfn("    -%s", slot.name);
          case int:    builder.appendfn("    -%s <integer>", slot.name);
          case float:  builder.appendfn("    -%s <float>", slot.name);
          case String: builder.appendfn("    -%s <string>", slot.name);
          default: unreachable("flag_print: unreachable");
        }
        builder.appendfn("        %s", slot.description);
      };
  };
}
