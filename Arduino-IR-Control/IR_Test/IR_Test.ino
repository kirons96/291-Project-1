#include <IRremote.h>

int RECEIVE_PIN= 3;
int START_STOP_PIN = 4;
int SET_PIN = 5;
int UP_PIN = 6;
int DOWN_PIN = 7;
IRrecv irreceiver(RECEIVE_PIN);
decode_results results;

void setup()
{
  Serial.begin(9600);
  irreceiver.enableIRIn(); // Start the receiver
  pinMode(START_STOP_PIN, OUTPUT);
  pinMode(SET_PIN, OUTPUT);
  pinMode(UP_PIN, OUTPUT);
  pinMode(DOWN_PIN, OUTPUT);
}

void loop() {
  if (irreceiver.decode(&results)) {
    if (results.value == 4294967295){
      irreceiver.resume(); //receive the next value
    }
    else if (results.value == 284153895){
      Serial.println("1");
      Serial.println(results.value);
      digitalWrite(START_STOP_PIN, LOW);
    }
    else if (results.value == 284106975){
      Serial.println("Set");
      Serial.println(results.value);
      digitalWrite(SET_PIN, LOW);
    }
    else if (results.value == 284139615){
      Serial.println("Up");
      Serial.println(results.value);
      digitalWrite(UP_PIN, LOW);
    }
    else if (results.value == 284098815){
      Serial.println("Down");
      Serial.println(results.value);
      digitalWrite(DOWN_PIN, LOW);
    }
    
    delay(1000);
    irreceiver.resume(); //receive the next value
    
    //reset pins
    digitalWrite(START_STOP_PIN, HIGH);
    digitalWrite(SET_PIN, HIGH);
    digitalWrite(UP_PIN, HIGH);
    digitalWrite(DOWN_PIN, HIGH);
  }
}
