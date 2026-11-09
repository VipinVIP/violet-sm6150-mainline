import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.lang.Register;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;
import ghidra.program.model.scalar.Scalar;
import java.util.*;

public class ImxRegs extends GhidraScript {
    @Override
    public void run() throws Exception {
        long[] targets = {0x3000L, 0x3002L, 0x3014L, 0x3040L, 0x301AL, 0x300AL};
        Map<String,Integer> hits = new TreeMap<>();
        InstructionIterator it = currentProgram.getListing().getInstructions(true);
        while (it.hasNext()) {
            Instruction ins = it.next();
            for (int i = 0; i < ins.getNumOperands(); i++) {
                Object[] objs = ins.getOpObjects(i);
                for (Object o : objs) {
                    if (o instanceof Scalar) {
                        long v = ((Scalar) o).getSignedValue();
                        for (long t : targets) {
                            if (v == t) {
                                Function f = getFunctionContaining(ins.getAddress());
                                String key = (f == null ? "?" : f.getName() + "@" + f.getEntryPoint()) + "  reg=0x" + Long.toHexString(t);
                                hits.merge(key, 1, Integer::sum);
                            }
                        }
                    }
                }
            }
        }
        for (Map.Entry<String,Integer> e : hits.entrySet())
            println("HIT " + e.getKey() + " x" + e.getValue());
        println("DONE hits=" + hits.size());
    }
}
