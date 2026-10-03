/* Extracted arithmetic order: char.c:2923-2941, battle_event.c:3435-3442,
 * char_item.c:344-354; source hashes and reviewed columns accompany JSON.
 * No game runtime or external libraries are used by this isolated oracle. */
#include <stdio.h>
static int loyalty(int owner, int charm, int pet, int modai, int variable, int trans) {
  int ai; double R;
  if (modai<=0) modai=100;
  R=1.10;
  ai=((owner*charm*R)/(pet*modai)*100);
  if(ai>100)ai=100;
  ai+=variable*0.01;
  if(trans>0)ai+=(140-owner)/2;
  if(ai<0)ai=0;
  if(ai>100)ai=100;
  return ai;
}
int main(int argc, char **argv) {
  (void)argv;
  if(argc>1) {
    int counts[]={0,1,5}, stats[]={0,99,100,101}, needs[]={0,1,5,6};
    for(int lv=1;lv<=30;lv+=29)
     for(unsigned n=0;n<3;n++)
      for(unsigned s=0;s<4;s++)
       for(unsigned d=0;d<4;d++)
        for(unsigned t=0;t<4;t++) {
         int error=0;
         if(counts[n]<=0 && 30>lv)error=1;
         else if(stats[s]<100)error=2;
         else if(stats[d]<100)error=3;
         else if(counts[n]<needs[t])error=4;
         printf("%d,%d,%d,%d,30,100,100,%d,%d\n",lv,counts[n],stats[s],stats[d],needs[t],error);
        }
    return 0;
  }
  int levels[]={1,2,79,80,120,139,140,141,142,143};
  int variables[]={-10000,-9999,-7001,-4000,-1,0,1,500,9999,10000};
  int counts[]={0,1,5};
  for(unsigned l=0;l<sizeof(levels)/sizeof(*levels);l++)
   for(unsigned v=0;v<sizeof(variables)/sizeof(*variables);v++)
    for(unsigned t=0;t<sizeof(counts)/sizeof(*counts);t++)
     for(int pet=1;pet<=120;pet+=119)
      for(int modai=0;modai<=300;modai+=150) {
       int ai=loyalty(levels[l],60,pet,modai,variables[v],counts[t]);
       int initial=loyalty(levels[l],60,pet,modai,0,counts[t]);
       int capture=initial>60?(60-initial)*100:0;
       printf("%d,%d,%d,%d,%d,%d,%d,%d\n",levels[l],60,pet,modai,variables[v],counts[t],ai,capture);
      }
  return 0;
}
