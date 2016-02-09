#include <IRremote.h>

int RECEIVE_PIN= 3;
IRrecv irreceiver(RECEIVE_PIN);
decode_results results;

void setup()
{
  Serial.begin(9600);
  irreceiver.enableIRIn(); // Start the receiver
}

void loop() {
  delay(100);
  if (irreceiver.decode(&results)) {
    if (results.value == 4294967295){
      irreceiver.resume(); //receive the next value
    }else if (results.value == 284098815){
      //Down
      Serial.println("Down");
      Serial.println(results.value);
    }else if (results.value == 284102895){
      //Left
      Serial.println("Left");
      Serial.println(results.value);
    }else if (results.value == 284131455){
      //C
      Serial.println("Right");
      Serial.println(results.value);
    }
    irreceiver.resume(); //receive the next value
  }
}
