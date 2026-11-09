import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.*;
import ghidra.program.model.scalar.Scalar;
import java.util.*;

public class ImxRegs2 extends GhidraScript {
    @Override
    public void run() throws Exception {
        long[] targets = {0x3014L, 0x301AL, 0x3028L, 0x302CL, 0x3040L, 0x3050L, 0x3002L, 0x3000L};
        Map<Long,Set<Long>> perFunc = new HashMap<>();
        Map<Long,String> names = new HashMap<>();
        InstructionIterator it = currentProgram.getListing().getInstructions(true);
        while (it.hasNext()) {
            Instruction ins = it.next();
            Function f = getFunctionContaining(ins.getAddress());
            if (f == null) continue;
            long fe = f.getEntryPoint().getOffset();
            for (int i = 0; i < ins.getNumOperands(); i++)
                for (Object o : ins.getOpObjects(i))
                    if (o instanceof Scalar) {
                        long v = ((Scalar) o).getUnsignedValue();
                        for (long t : targets)
                            if (v == t) {
                                perFunc.computeIfAbsent(fe, k -> new HashSet<>()).add(t);
                                names.put(fe, f.getName());
                            }
                    }
        }
        for (Map.Entry<Long,Set<Long>> e : perFunc.entrySet()) {
            Set<Long> s = e.getValue();
            if (s.size() >= 3)
                println(String.format("FUNC %s@%x regs=%s", names.get(e.getKey()), e.getKey(), s.toString()));
        }
        println("DONE");
    }
}
