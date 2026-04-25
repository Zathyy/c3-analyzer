module test;
import std;
import dessert;
import json;
import csv;

struct Animal {
  String name;
  String specie;
}

fn void? Animal.serialize(&self, Serializer serializer) => 
  ser::impl_serialize(self, serializer);

fn void? Animal.deserialize(&self, Deserializer deserializer) => 
  des::impl_deserialize(self, deserializer);


enum State : (String name) {
  WAITING { "wait" },
  SLEEPING { "sleep" },
  RUNNING { "run" },
}

fn void? State.serialize(&self, Serializer serializer) => 
  ser::impl_serialize(self, serializer);

fn void? State.deserialize(&self, Deserializer deserializer) => 
  des::impl_deserialize(self, deserializer);

struct Person {
  int age;
  String name;
  Animal[] pets @DField({ .skip_if_empty = true });
  Person* friend @DField({ .rename = "my_friend" });
  bool is_cool @DField({ .skip = true });
  long a;
  State state;
}

fn bool Person.skip_serializing_age(&self) {
  return self.age == 24;
}

fn void? Person.serialize(&self, Serializer serializer) => 
  ser::impl_serialize(self, serializer);

fn void? Person.deserialize(&self, Deserializer deserializer) =>
  des::impl_deserialize(self, deserializer);


fn void t() @test {
  Animal sharpie = { .name = "Sharpie", .specie = "Cat" };
  Person connor = { .age = 20, .name = "Connor", .is_cool = true };
  Person amenda = { .age = 24, .name = "Amenda", .is_cool = false };
  connor.pets = { sharpie };
  connor.friend = &amenda;

  JsonSerializer s = json::serializer();
  JsonValue json = ser::serialize(&s, connor)!!;
  defer json.free();

  io::printn(json.to_pretty_string());

  Person p = des::deserialize{Person}(&&json::deserializer(json.to_string()))!!;

  io::printfn("%s\n%s", string::from_struct(mem, p), string::from_struct(mem, p.pets[0]));

  io::printfn("%s", string::from_struct(mem, *p.friend));

  assert(p.friend != null);
  assert(p.friend.name == "Amenda");
  assert(p.friend.age == 0);


  // io::printfn("Person named %s with a %s named %s", p.name, p.pets[0].specie, p.pets[0].name);
}


const String TEST_DATA = `{
  "name": "bash",
  "arguments": "{\"command\": \"python --version\"}",
  "x": 505874924095815700,
  "oh": true,
  "wait": null
}`;

struct Function @DStruct({ .deny_unknown_fields = true })
{
  String name;
  String arguments;
  long x;
}

fn void? Function.serialize(&self, Serializer serializer) =>
  ser::impl_serialize(self, serializer);

fn void? Function.deserialize(&self, Deserializer deserializer) =>
  des::impl_deserialize(self, deserializer);

fn void test_escape() @test {
  Function fun = {
    .name = "bash",
    .arguments = "{\"command\": \"python --version\"}",
  };

  JsonSerializer s = json::serializer();
  JsonValue json = ser::serialize(&s, fun)!!;
  json.print()!!;
  io::printfn("\njson => %s", json.to_string()!!);

  Function? f = des::deserialize{Function}(&&json::deserializer(TEST_DATA));
  if (catch err = f) {
    assert(err == des::UNKNOWN_FIELD);
  } else {
    // should have failed because deny_unknown_fields is true
    assert(false);
  }
}


struct Meteo {
  String date;
  double temperature;
  double pressure;
  String locatisation;
}

fn void? Meteo.serialize(&self, Serializer serializer) =>
  ser::impl_serialize(self, serializer);

fn void test_csv() @test {
  Meteo[10] meteos = {
    { .date = "2024-01-01", .temperature = -3.2, .pressure = 1013.5, .locatisation = "Paris" },
    { .date = "2024-01-02", .temperature =  1.5, .pressure = 1008.2, .locatisation = "Lyon" },
    { .date = "2024-01-03", .temperature =  5.8, .pressure = 1005.7, .locatisation = "Marseille" },
    { .date = "2024-01-04", .temperature = 12.3, .pressure = 1020.1, .locatisation = "Bordeaux" },
    { .date = "2024-01-05", .temperature =  8.0, .pressure = 1017.4, .locatisation = "Toulouse" },
    { .date = "2024-01-06", .temperature = -1.1, .pressure = 1002.9, .locatisation = "Lille" },
    { .date = "2024-01-07", .temperature =  3.4, .pressure = 1011.3, .locatisation = "Nantes" },
    { .date = "2024-01-08", .temperature = 15.6, .pressure = 1018.8, .locatisation = "Nice" },
    { .date = "2024-01-09", .temperature =  7.2, .pressure = 1009.6, .locatisation = "Strasbourg" },
    { .date = "2024-01-10", .temperature =  9.9, .pressure = 1014.0, .locatisation = "Rennes" },
  };

  CSVSerializer s_csv = csv::serializer();
  CSVDocument csv = ser::serialize(&s_csv, meteos)!!;

  io::printfn("%s", csv.to_string());
}


const String TEST_DATA_2 = `{
  "name": "bash",
  "arguments": "{\"command\": \"python --version\"}",
  "x": 505874924095815.22,
  "oh": true,
  "wait": null
}`;

fn void test_escape2() @test {
  Object* f = des::deserialize{Object*}(&&json::debug_deserializer(TEST_DATA_2))!!;
  io::printfn("\nf => %s", string::from_struct(mem, f));
}
