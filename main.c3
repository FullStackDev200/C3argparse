module test;
import std::io;
import argparse;
import std::collections::map;
import std::collections::list;

struct Vector (Printable)
{
    int x;
    int y;
}

fn void main(String[] args) {
  bool run = false;
  bool help = false;
  int count = 69;
  float measure = 420.0;
  String name = "Viu";
  Vector vector = {0, 0};


  argparse::@flag(run, "run", "run something");
  argparse::@flag(help, "help", "print this help");
  argparse::@flag(count, "count", "number", is_default: true);
  argparse::@flag(measure, "measure", "measure of things", is_required: true);
  argparse::@flag(name, "name", "name of something");

  @catch(argparse::flag_parse(args));

  if(help){
    DString sb = dstring::temp();
    argparse::flag_print_options(&sb);
    io::printn(sb);
 }
  io::printfn("Run: %s", run);
  io::printfn("help: %s", help);
  io::printfn("count: %s", count);
  io::printfn("measure: %s", measure);
  io::printfn("name: %s", name);
}
