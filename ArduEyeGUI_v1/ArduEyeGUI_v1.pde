/*
arduGUI_v1.c

Basic GUI to read text, images, vectors, and points from ArduEye

Working revision started February 16, 2011
February 17, 2011: renamed to ArduEyeGUI_v1, escape character changed to 27
*/
/*
===============================================================================
Copyright (c) 2012 Centeye, Inc. 
All rights reserved.

Redistribution and use in source and binary forms, with or without 
modification, are permitted provided that the following conditions are met:

    Redistributions of source code must retain the above copyright notice, 
    this list of conditions and the following disclaimer.
    
    Redistributions in binary form must reproduce the above copyright notice, 
    this list of conditions and the following disclaimer in the documentation 
    and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY CENTEYE, INC. ``AS IS'' AND ANY EXPRESS OR 
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF 
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO 
EVENT SHALL CENTEYE, INC. OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, 
INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, 
BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, 
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY 
OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING 
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, 
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

The views and conclusions contained in the software and documentation are 
those of the authors and should not be interpreted as representing official 
policies, either expressed or implied, of Centeye, Inc.
===============================================================================*/

//***********************************************************
//Imported Libraries
import processing.serial.*;  //handles serial comms with Arduino
import controlP5.*;  //provides GUI objects like buttons,textfields, etc.

//***********************************************************
//Global Variables

//Serial Variables
Serial myPort;            //serial port instance
int current_port=0;       //current serial port
int default_port=0;       //default port
int baud_rate=115200;     //baud rate (115200 is fine for me)

//CONTROLP5 Objects
ControlP5 controlP5;      //controlP5 object for GUI object class
Textfield myTextfield;    //textfield for typing serial commands  
DropdownList com_ports;   //dropdown list of available com ports
Button myButton;          //button to connect to Arduino
int state=0;              //state of button

//Serial log text display
ArrayList text_log;          //array list of strings to be displayed
String string_buffer="";     //buffer for incoming characters    
int string_length=0;         //length of string buffer
int line_width=40;           //number of chars per line of text
int num_lines=25;            //number of lines of text

//***********************************************************
//Display Variables
PFont myFont;              //The display font:

PImage img;                //main image
PImage overlay_image;      //overlay image (for highlighting points,etc.)

int vector_x=0;            //x display vector
int vector_y=0;            //y display vector

//***********************************************************
//COMM Variables

final int escape=27;         //ESCAPE SPECIAL CHAR
final int start_packet=1;    //START PACKET
final int end_packet=2;      //END PACKET
final int image_data=2;      //IMAGE DATA
final int pixel_data=4;      //PIXEL DATA
final int vector_data=6;     //VECTOR DATA

byte[] data=new byte[4096];  //packet buffer
int data_index=0;            //buffer index

int store_byte=0;            //whether to store byte in buffer
int in_packet=0;             //whether we are currently in a packet           
byte escape_detected=0;      //whether last byte was an escape

//***********************************************************
//***********************************************************


//***********************************************************
//setup function
void setup() {
  
  size(800, 500);  //set size of window
  
  myFont = loadFont("Verdana-7.vlw");  //load font
  textFont(myFont, 12);  //set font
 
  //automatically connect to first serial port
  myPort = new Serial(this, Serial.list()[default_port], baud_rate);
  myPort.buffer(0);  //interrupt on every byte

  //text_log contains serial log display strings
  text_log=new ArrayList();
  
  //initialize ControlP5
  controlP5 = new ControlP5(this);

  //setup textfield for serial_out data
  myTextfield = controlP5.addTextfield("serial_out", 50, 50, 160, 20);
  myTextfield.setFocus(true);  //force focus
  myTextfield.setColorBackground(color(200));  //set colors
  myTextfield.setColorActive(color(0));
  myTextfield.setColorForeground(color(0));
  myTextfield.setColorLabel(color(0));
  myTextfield.setColorValue(color(0));
  myTextfield.setColorValueLabel(color(0));
  myTextfield.setColorCaptionLabel(color(0));
 
  //setup button for connect/disconnect Arduino
  myButton=controlP5.addButton("connect",0,130,10,80,20);
  myButton.setColorBackground(color(200));  //set colors
  myButton.setColorActive(color(255));
  myButton.setColorForeground(color(255));
  myButton.setColorLabel(color(0));
  
  //setup dropdown menu for current serial ports
  com_ports=controlP5.addDropdownList("com-ports", 10, 30, 100, 80);
  com_ports.setItemHeight(20);
  com_ports.setBarHeight(20);
  com_ports.captionLabel().set("SELECT COM PORT");
  com_ports.captionLabel().style().marginTop = 5;
  com_ports.captionLabel().style().marginLeft = 3;
  com_ports.valueLabel().style().marginTop = 3;
  for (int i=0;i<Serial.list().length;i++) {  //add serial list to dropdowns
    com_ports.addItem(Serial.list()[i], i);
  }
  com_ports.setColorBackground(color(200));
  com_ports.setColorActive(color(255));
  com_ports.setColorForeground(color(255));
  com_ports.setColorLabel(color(0));

  //initialize image and overlay_image
  img = createImage(16, 16, ALPHA);
  overlay_image = createImage(16, 16, ARGB);
}


//***********************************************************
//Draw Function
void draw() {
  
  background(0);              //set background color
  stroke(color(255, 0, 0));   //set draw color
  fill(255,255,255);          //set text fill color
  
  text("Send: ", 10, 63);     //display this to left of text field

  image(img, 350, 50, 400, 400);  //display image
  image(overlay_image, 350, 50, 400, 400);  //dispay overlay image
  
  for(int i=0;i<text_log.size();i++)  //display text_log strings
    text((String)text_log.get(i),10,100+i*15);

//  if ((vector_x!=0) || (vector_y!=0))  //if non-zero, display vector
    line(550, 250, 550+vector_x, 250+vector_y);
}

//***********************************************************
//serialEvent: Interrupts whenever a byte is received from
//serial port
void serialEvent(Serial p) {

  int new_byte=0;  //incoming byte
  
 
  while (myPort.available () > 0)  //read all available bytes
  {
    new_byte=myPort.read();  //read next byte
    store_byte=1;  //default is store byte in buffer

    if (escape_detected==1)  //if last byte was escape, check for special chars
    {
      switch(new_byte)
      {
        case start_packet:  //special char start packet
          in_packet=1;      //we are now in a packet
          data_index=0;     //first byte of packet
          store_byte=0;     //don't store this
          break;
        case end_packet:    //special char end packet
          store_byte=0;     //don't store this
          
          if (in_packet==1)  //if we were in a packet
            processPacket(data, data_index);  //process packet
          
          in_packet=0;      //we are no longer in a packet
          break;
        case escape:        //this is a double escape
          store_byte=1;     //this byte is data, store it
          break;
        default:
          store_byte=0;    //unknown escape char, don't store
          break;
      }
      escape_detected=0;  //end of escape sequence
    }
    else //if last character wasn't escape
    {
      if (new_byte==escape)  //is this byte escape
      {
        escape_detected=1;  //mark as escape sequence
        store_byte=0;       //don't store
      }
    }

    if (store_byte==1)  //if this is a byte of data
    {
      if (in_packet==1)  //if we're in a packet
      {
        data[data_index]=(byte)new_byte;  //store in packet buffer
        data_index++;  //increase packet size
      }
      else   //if the data isn't in packet, assume its text 
      {
        string_buffer=string_buffer+(char)new_byte;  //add to string buffer
        string_length++;  //increase string_length
        
        //if string_length is as wide as screen or line feed received
        //then we want to create a new string for the next line
        if((string_length==line_width)||((char)new_byte=='\n'))
        {
         text_log.add(string_buffer);  //add finished string to text log
         string_buffer="";  //clear string buffer
         string_length=0;   //set string length to zero
         if(text_log.size()>=num_lines)  //if text_log strings reach max
           text_log.remove(0);           //then remove oldest string
        }
      }
    }
  }
}

//***********************************************************
//processPacket: update display based on received packets
void processPacket(byte[] packet, int packet_length)
{
  int minimum=4096;     //min pixel
  int maximum=-4096;    //max pixel
  float mult_factor=0;  //scale factor
  int ctr=0;            //counter
  
  switch(packet[0])  //switch of packet ID
  {
  
    case image_data:  //if image packet received
    
      //create blank image of given size
      // [rows] [cols] are bytes 2 and 3
      img = createImage(packet[1], packet[2], ALPHA);
    
      img.loadPixels();  //load pixel array
      
      int[] pix1=new int[img.pixels.length];  //create integer array
    
      //each pixel is two bytes, form integer from then
      for (int i = 3; i < img.pixels.length*2+2; i+=2) 
      {
        pix1[ctr]=(int)((data[i])<<8)+data[i+1];  //combine to get pixel
        if(pix1[ctr]>maximum) maximum=pix1[ctr];  //find max
        if(pix1[ctr]<minimum) minimum=pix1[ctr];  //find min
        ctr++;
      }
   
      //mult_factor maps pixel values onto 0->255
      mult_factor=255/abs((float)maximum-(float)minimum);
      
      //set image pixels based on data
      for (int i = 0; i < img.pixels.length; i++) 
         //img.pixels[i] = color((255-(int)((pix1[i]-minimum)*mult_factor)));
         img.pixels[i] = color(((int)((pix1[i]-minimum)*mult_factor)));
         
      img.updatePixels();  //update pixels
      break;
      
  case pixel_data:  //if points data received
  
    //create image based on [rows] [cols], bytes 2 and 3
    overlay_image = createImage(packet[1], packet[2], ARGB);
    
    overlay_image.loadPixels();  //load pixels
    
    //make all pixels transparent
    for (int i = 0; i < overlay_image.pixels.length; i++) 
      overlay_image.pixels[i] = 0;

    //for each pair of pixels, color the proper pixel red
    for (int i=3; i<packet_length-1;i+=2)
      overlay_image.pixels[(packet[i]*packet[1]+packet[i+1])]=color(255, 0, 0);
   
    overlay_image.updatePixels();  //update pixels
    break;
    
  case vector_data:    //if vector received 
    vector_x=-packet[3];    //x component of vector
    vector_y=-packet[4];   //y component of vector
    break;
    
  default:break;
  }
}


//***********************************************************
//controlEvent- triggers when dropdown is selected
void controlEvent(ControlEvent theEvent) {
 
  if (theEvent.isGroup()) {   //if control event received from dropdown
    if ((theEvent.group().name()).equals("com-ports"))
      //save choice as current port index
      current_port=(int)theEvent.group().value();  
  } 
}

//***********************************************************
//serial_out- triggers whenever text is entered in textfield
public void serial_out(String theText) {
  
  // receiving text from textfield
  if (theText.equals("clr"))  //if clear command
  {
    text_log.clear();  //clear text_log
  }
  else  
  {
    myPort.write(theText);  //send over serial port
  }
}

//***********************************************************
//connect- triggers whenever button is pushed
public void connect(int theValue) {
  
  if(state==0)  //we want to connect to the Arduino
  {
    state=1;  //change state
    
    //connect to current serial port
    myPort = new Serial(this, Serial.list()[current_port], baud_rate);
    myPort.buffer(0);  //interupt on every char
    myPort.clear();    //clear port
   
    delay(500);        //small delay 
    String out="!0";  //send stop to Arduino if its flooding serial port with output
    myPort.write(out);  
    
    delay(500);        //small delay
    text_log.clear();  //clear text log 
    text_log.add("Are you there, Arduino?\n");  //ask arduino to respond
   
    out="!1";         //send start to Arduino (sends text in response)
    myPort.write(out);
    
    myButton.setLabel("disconnect");  //change button text
  }
  else
  {
    state=0;  //change state
    
    String out="!0";  //send stop to Arduino
    myPort.write(out);
    
    text_log.add("Goodbye, Arduino...\n");  //to text log
    
    myButton.setLabel("connect");  //change button text
   
    delay(500);  //small delay so Arduino can respond
    myPort.stop();  //stop port   
  }
}

//***********************************************************
//stop- executes when window is closed
void stop()
{
  String out="!0";  //stop arduino
  myPort.write(out);
  
  myPort.stop();  //stop serial port
  
  super.stop();  //call real stop function
}

